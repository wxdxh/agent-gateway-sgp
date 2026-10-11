# Gemini Enterprise와 Agent Gateway, SGP를 활용한 자율형 AI 에이전트 보안 거버넌스

## 개요

대규모 언어 모델(LLM) 기반의 자율형 AI 에이전트는 스스로 추론하고 워크플로를 오케스트레이션하며, 계좌 이체 API나 핵심 데이터베이스 같은 엔터프라이즈 백엔드 도구를 직접 호출할 수 있습니다. 하지만 에이전트에게 백엔드 시스템에 대한 직접적인 네트워크 접근 권한을 부여하면 프롬프트 인젝션, 모델 환각, 비인가 고액 거래로 인한 보안 및 금융 컴플라이언스 리스크가 발생합니다.

이 실습에서는 에이펙스 자산운용(Apex Asset Management)의 금융 보안 시나리오를 바탕으로, 에이전트 애플리케이션 코드를 수정하지 않고 네트워크 경계에서 자연어 기반의 비즈니스 규정을 실시간으로 강제하는 아키텍처를 구현합니다. Gemini Enterprise Agent Runtime에서 동작하는 대화형 뱅킹 에이전트(`gemini-3.8-flash`, Global 엔드포인트)가 Google Cloud Agent Gateway(`agent-egress`)와 시맨틱 거버넌스 정책(Semantic Governance Policies, SGP)을 경유하여 Cloud Run 기반의 뱅킹 MCP(Model Context Protocol) 서버를 호출하도록 구성합니다.

에이전트 내부의 시스템 프롬프트만으로는 우회 공격이나 런타임 오작동을 완벽히 통제하기 어렵습니다. Agent Gateway와 SGP를 결합하면 모든 아웃바운드 도구 호출을 네트워크 경계에서 가로채어 "1회 이체 금액이 100만 원(`amount <= 1000.0`)을 초과하는 모든 송금 요청은 차단한다"와 같은 자연어 비즈니스 정책을 코드 변경 없이 강제하고 Cloud Logging에 감사 로그를 기록할 수 있습니다.

| 단계 | 구성 요소 | 역할 및 트래픽 흐름 |
| :--- | :--- | :--- |
| 1. 사용자 요청 | 금융 고객 김민준 (`CUST005`) → Gemini Enterprise 에이전트 | 3-Turn 대화형 요청 전달 (`gemini-3.8-flash`, Global API) |
| 2. 호출 가로채기 | Gemini Enterprise 에이전트 → Agent Gateway (`agent-egress`) | 아웃바운드 MCP 도구 호출을 네트워크 경계에서 가로채기 및 TLS 복호화 |
| 3. 카탈로그 검증 | Agent Registry ↔ Agent Gateway | 허가된 MCP 도구 스키마 및 시스템 API Allowlist 확인 (`roles/iap.egressor`) |
| 4. 정책 심사 (PSC) | Agent Gateway → SGP 정책 엔진 (`policy.internal.`) | PSC 사설망을 통해 1회 이체 한도(100만 원 / `USD 1000`) 초과 여부 실시간 심사 |
| 5. 백엔드 실행 및 감사 | Agent Gateway → Cloud Run (`banking-mcp-server`) | `ALLOW` 판정 시 Cloud Run MCP 서버로 전달, `DENY` 시 차단 및 Cloud Logging 기록 |

### 학습 목표

이 실습에서는 Google Cloud Shell을 사용하여 다음 작업을 수행합니다.

1. Agent Gateway(`agent-egress`) 구성을 위한 필수 Google Cloud API 활성화 및 관리형 서비스 에이전트(`roles/agentgateway.serviceAgent`) IAM 권한 부여
2. 리전 관리형 프록시 전용 서브넷(`proxy-only-subnet`), Network Attachment(`agent-gateway-na`), `AGENT_TO_ANYWHERE` 모드의 Agent Gateway 배포
3. Google Cloud Run에 에이펙스 자산운용의 4가지 금융 도구를 제공하는 뱅킹 MCP 서버(`banking-mcp-server`) 컨테이너 빌드 및 배포
4. Agent Registry에 뱅킹 MCP 도구 명세(`toolspec.json`) 및 Gemini Enterprise Global API(`https://aiplatform.googleapis.com`)를 포함한 시스템 엔드포인트 등록과 IAP Egress(`roles/iap.egressor`) 권한 부여
5. Google ADK(Agent Development Kit)로 구현된 대화형 뱅킹 에이전트(`gemini-3.8-flash`, `GOOGLE_CLOUD_LOCATION=global`)를 Gemini Enterprise Agent Runtime에 비동기(`--no-wait`)로 배포
6. 백그라운드에서 에이전트가 배포되는 동안 SGP 정책 엔진 활성화, Private Service Connect(PSC) 엔드포인트(`sgp-psc-endpoint`) 및 프라이빗 Cloud DNS(`policy.internal.`) 구성
7. Service Extensions(`AuthzExtension`), 네트워크 보안 인가 정책(`AuthzPolicy`), 100만 원 초과 송금을 차단하는 자연어 시맨틱 거버넌스 정책(`high-value-limit`) 생성
8. Cloud Shell에서 3-Turn 금융 거래 시나리오(본인 확인, 5만 원 소액 이체 `ALLOW`, 200만 원 고액 이체 `DENY`) 실행 및 Cloud Logging 감사 로그 확인

### 사전 요구사항

* Google Cloud 콘솔 및 Cloud Shell 기본 사용법
* VPC 서브넷, Private Service Connect(PSC), Cloud DNS 등 Google Cloud 네트워킹 기초 개념
* Python 기반 AI 에이전트(ADK) 및 Model Context Protocol(MCP)의 기본 동작 원리

## 실습 환경 설정 및 요구사항

### 실습 시작 및 Google Cloud 콘솔 로그인

1. 화면 좌측 상단의 **Start Lab** 버튼을 클릭합니다. 실습이 시작되면 임시 Google Cloud 프로젝트와 로그인 자격 증명(**Username**, **Password**)이 발급됩니다.
2. 개인 계정과의 충돌 및 의도치 않은 과금을 방지하기 위해 반드시 브라우저의 **시크릿 창**(Incognito Window)에서 실습을 진행합니다.
3. 좌측 패널의 **Open Google Cloud console** 버튼을 우클릭하여 시크릿 창에서 열고, 발급된 **Username**과 **Password**를 복사하여 로그인합니다.
4. 약관 동의 화면이 나타나면 동의 후 다음으로 진행합니다. 임시 계정이므로 복구 옵션이나 2단계 인증은 설정하지 않습니다.

<ql-warningbox><strong>주의:</strong> 실습을 완전히 마칠 때까지 좌측 상단의 <strong>End Lab</strong> 버튼을 클릭하지 마세요. <strong>End Lab</strong>을 클릭하면 진행 중인 작업과 임시 Google Cloud 프로젝트가 즉시 삭제됩니다.</ql-warningbox>

### Cloud Shell 활성화

Google Cloud 콘솔 우측 상단 툴바에서 **Activate Cloud Shell** 아이콘을 클릭하여 Cloud Shell 터미널을 엽니다. 안내 창이 나타나면 **Continue**와 **Authorize**를 차례대로 클릭합니다.

### 실습 리포지토리 및 CLI 도구 준비

실습을 시작하면 사전 프로비저닝 스크립트(`terraform/main.tf`)가 백그라운드에서 실행되어 필수 Google Cloud API, 전용 VPC 네트워크(`apex-wealth-vpc`), 리전 서브넷(`apex-subnet`, `10.10.0.0/24`), 리전 관리형 프록시 전용 서브넷(`proxy-only-subnet`, `10.11.13.0/24`), 프라이빗 Cloud DNS 영역(`policy-engine-zone`), PSC 내부 고정 IP(`sgp-psc-ip`) 및 기본 서비스 에이전트 IAM 권한을 자동으로 준비합니다.

Cloud Shell 터미널이 열리면 아래 명령어를 순서대로 실행하여 환경을 준비합니다.

1. 현재 로그인된 계정과 활성화된 프로젝트 ID를 확인합니다.

<ql-code-block language="bash">
gcloud auth list
gcloud config list project
</ql-code-block>

2. 프로젝트 ID가 비어 있다면 좌측 실습 안내 패널에 표시된 **Project ID**를 설정합니다.

<ql-code-block language="bash" templated>
gcloud config set project {{{project_0.project_id|PROJECT_ID}}}
</ql-code-block>

3. Cloud Shell 홈 디렉터리(`$HOME`)에 실습 코드 리포지토리를 복제하고 작업 폴더로 이동합니다.

<ql-code-block language="bash">
cd ~
git clone https://github.com/wxdxh/agent-gateway-sgp.git
cd ~/agent-gateway-sgp
chmod +x *.sh
</ql-code-block>

4. Gemini Enterprise Agent Runtime 패키징 및 배포에 사용하는 `uv`와 `google-agents-cli`를 설치합니다.

<ql-code-block language="bash">
curl -LsSf https://astral.sh/uv/install.sh | sh
export PATH="$HOME/.local/bin:$PATH"
echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.bashrc

uv tool install google-agents-cli
agents-cli --version
</ql-code-block>

5. 공통 환경 변수 스크립트(`env.sh`)를 로드하여 프로젝트 메타데이터와 VPC(`apex-wealth-vpc`), 서브넷(`apex-subnet`) 정보가 정상적으로 불러와지는지 확인합니다.

<ql-code-block language="bash">
cd ~/agent-gateway-sgp
source env.sh
</ql-code-block>

정상적으로 로드되면 다음과 같은 환경 정보가 출력됩니다.

<ql-code-block output>
Project ID:     qwiklabs-gcp-xx-xxxxxxxxxxxx
Project Number: 1080321871308
Location:       us-central1
VPC Network:    apex-wealth-vpc
VPC Subnet:     apex-subnet
Agent GW SA:    serviceAccount:service-1080321871308@gcp-sa-agentgateway.iam.gserviceaccount.com
</ql-code-block>

<ql-infobox><strong>참고:</strong> 실습 도중 Cloud Shell 세션이 재연결되더라도 <code>$HOME/agent-gateway-sgp</code> 디렉터리와 <code>.env.runtime</code> 파일은 유지됩니다. 터미널이 재시작된 경우 <code>cd ~/agent-gateway-sgp &amp;&amp; source env.sh &amp;&amp; [[ -f .env.runtime ]] &amp;&amp; source .env.runtime</code> 명령어를 실행하면 이어서 진행할 수 있습니다.</ql-infobox>

## 작업 1. 필수 Google Cloud API 확인, 서비스 에이전트 IAM 구성 및 백그라운드 예열

첫 번째 작업에서는 Agent Registry, Model Armor, Telemetry 등을 포함한 필수 API와 Google 관리형 서비스 에이전트(`service-${PROJECT_NUM}@gcp-sa-agentgateway.iam.gserviceaccount.com`, `service-${PROJECT_NUM}@gcp-sa-aiplatform.iam.gserviceaccount.com`)의 IAM 권한을 구성합니다. 또한 실습 대기 시간을 단축하기 위해 에이전트의 고유 ID(`AGENT_IDENTITY`)를 선행 생성하고, 백그라운드에서 Cloud Run 뱅킹 MCP 서버와 SGP 정책 엔진 예열(Warm-up)을 시작합니다.

### 환경 초기화 및 서비스 에이전트 IAM 구성 스크립트 실행

1. Cloud Shell에서 `./01-setup-env.sh` 스크립트를 실행하여 필수 API 활성화 상태 확인, Agent Gateway 및 Vertex AI 서비스 에이전트 IAM 권한 부여, `conversational-banking` 에이전트 ID(`principal://...`) 선행 생성 및 백그라운드 예열 작업을 수행합니다.

<ql-code-block language="bash">
cd ~/agent-gateway-sgp
source env.sh
./01-setup-env.sh
</ql-code-block>

2. Agent Gateway 서비스 에이전트(`AGW_SA`)에 에이전트 트래픽 중계 및 정책 심사에 필요한 4가지 핵심 IAM 역할(`roles/agentgateway.serviceAgent`, `roles/aiplatform.user`, `roles/modelarmor.user`, `roles/agentregistry.viewer`)이 정상적으로 바인딩되었는지 확인합니다.

<ql-code-block language="bash">
gcloud projects get-iam-policy "${PROJECT_ID}" \
  --flatten="bindings[].members" \
  --filter="bindings.members:${AGW_SA}" \
  --format="table(bindings.role)"
</ql-code-block>

## 작업 2. Agent Gateway 네트워크 기반 및 agent-egress 게이트웨이 배포

이 작업에서는 Gemini Enterprise Agent Runtime에서 외부 MCP 서버 및 시스템 API로 나가는 아웃바운드 트래픽을 통제하는 Agent Gateway(`agent-egress`)를 구성합니다. 사전 프로비저닝된 리전 관리형 프록시 전용 서브넷(`proxy-only-subnet`)과 프라이빗 Cloud DNS 영역(`policy-engine-zone`)을 확인하고, Network Attachment(`agent-gateway-na`)를 생성한 뒤 `AGENT_TO_ANYWHERE` 모드의 게이트웨이를 배포합니다.

### 리전 관리형 프록시 서브넷 확인 및 Network Attachment 생성

1. Agent Gateway 내부 Envoy 프록시 인스턴스가 사용할 리전 관리형 프록시 전용 서브넷(`proxy-only-subnet`, `10.11.13.0/24`)과 DNS 피어링용 프라이빗 Cloud DNS 영역(`policy-engine-zone`, `policy.internal.`)이 준비되어 있는지 확인합니다(없는 경우 자동으로 생성합니다).

<ql-code-block language="bash">
cd ~/agent-gateway-sgp
source env.sh

if ! gcloud compute networks subnets describe proxy-only-subnet --region="${LOCATION}" --project="${PROJECT_ID}" &>/dev/null; then
  gcloud compute networks subnets create proxy-only-subnet \
    --network="${NETWORK_NAME}" \
    --region="${LOCATION}" \
    --range="10.11.13.0/24" \
    --purpose=REGIONAL_MANAGED_PROXY \
    --role=ACTIVE \
    --project="${PROJECT_ID}"
fi

if ! gcloud dns managed-zones describe policy-engine-zone --project="${PROJECT_ID}" &>/dev/null; then
  gcloud dns managed-zones create policy-engine-zone \
    --description="Private zone for internal SGP service" \
    --dns-name="policy.internal." \
    --visibility=private \
    --networks="${NETWORK_NAME}" \
    --project="${PROJECT_ID}"
fi
</ql-code-block>

2. Google 관리형 테넌트 프로젝트에서 실행되는 Agent Gateway가 실습 프로젝트의 VPC(`apex-subnet`)로 이그레스 트래픽을 전달할 수 있도록 Network Attachment(`agent-gateway-na`)를 생성합니다.

<ql-code-block language="bash">
gcloud compute network-attachments create agent-gateway-na \
  --region="${LOCATION}" \
  --subnets="${SUBNET_NAME}" \
  --connection-preference=ACCEPT_AUTOMATIC \
  --project="${PROJECT_ID}" || true
</ql-code-block>

### agent-egress 게이트웨이 구성 파일 작성 및 배포

1. `AGENT_TO_ANYWHERE` 거버넌스 경로, Agent Registry 연동, Network Attachment 및 `policy.internal.` 도메인에 대한 DNS 피어링 설정이 포함된 `agent-gateway-vpc-egress.yaml` 파일을 작성합니다.

<ql-code-block language="bash">
cat > agent-gateway-vpc-egress.yaml << EOF
name: projects/${PROJECT_ID}/locations/${LOCATION}/agentGateways/agent-egress
protocols:
  - MCP
googleManaged:
  governedAccessPath: AGENT_TO_ANYWHERE
registries:
  - //agentregistry.googleapis.com/projects/${PROJECT_ID}/locations/${LOCATION}
networkConfig:
  egress:
    networkAttachment: projects/${PROJECT_ID}/regions/${LOCATION}/networkAttachments/agent-gateway-na
  dnsPeeringConfig:
    domains:
      - policy.internal.
    targetProject: ${PROJECT_ID}
    targetNetwork: projects/${PROJECT_ID}/global/networks/${NETWORK_NAME}
EOF
</ql-code-block>

2. 작성한 매니페스트 파일을 임포트하여 `agent-egress` 게이트웨이를 생성합니다.

<ql-code-block language="bash">
gcloud network-services agent-gateways import agent-egress \
  --source=agent-gateway-vpc-egress.yaml \
  --location="${LOCATION}" \
  --project="${PROJECT_ID}"
</ql-code-block>

<ql-infobox><strong>팁:</strong> 위 과정은 <code>./02-setup-agent-gateway.sh</code> 스크립트로도 실행할 수 있습니다.</ql-infobox>

3. 배포된 `agent-egress` 게이트웨이의 상세 구성을 조회합니다.

<ql-code-block language="bash">
gcloud network-services agent-gateways describe agent-egress \
  --location="${LOCATION}" \
  --project="${PROJECT_ID}" \
  --format="yaml(name,googleManaged,networkConfig)"
</ql-code-block>

<ql-multiple-choice-probe stem="Agent Gateway(agent-egress)가 Gemini Enterprise 에이전트에서 외부 MCP 도구로 나가는 아웃바운드 호출을 통제할 때 사용하는 governedAccessPath 모드는 무엇입니까?"
                          optionTitles='[
                            "AGENT_TO_ANYWHERE",
                            "ANYWHERE_TO_AGENT",
                            "DIRECT_VPC_EGRESS",
                            "PUBLIC_INGRESS_ONLY"
                          ]'
                          answerIndex="0"
                          shuffle>
</ql-multiple-choice-probe>

아래 **Check my progress** 버튼을 클릭하여 작업 완료 여부를 확인합니다.
<ql-activity-tracking step=1>
    작업 1~2: Agent Gateway 네트워킹 및 agent-egress 게이트웨이 구성 확인
</ql-activity-tracking>

## 작업 3. Cloud Run에 에이펙스 자산운용 뱅킹 MCP 서버 배포 및 권한 설정

이 작업에서는 에이펙스 자산운용의 뱅킹 백엔드 역할을 하는 MCP 서버(`banking-mcp-server`)를 Google Cloud Run에 배포하고 권한을 구성합니다. 이 서버는 계좌 조회(`get_account`), 전화번호로 고객 조회(`lookup_customer_by_phone`), 간편 송금(`transfer_to_phone`), 공과금 납부(`pay_bill`)의 4가지 도구를 JSON-RPC 2.0(`/mcp`) 및 도구 명세 조회(`/tools`) 엔드포인트로 제공합니다.

### 뱅킹 MCP 서버 배포 확인, 도구 검증 및 Invoker 권한 부여

1. `./03-deploy-mcp.sh` 스크립트를 실행하여 Cloud Run `banking-mcp-server` 배포 완료 여부를 확인(작업 1에서 백그라운드로 시작된 빌드가 완료되었으면 즉시 재사용)하고, 서비스 URL(`MCP_URL`)을 `.env.runtime`에 저장한 뒤 `/tools` 스키마 검증과 `roles/run.servicesInvoker` 권한 부여를 수행합니다.

<ql-code-block language="bash">
cd ~/agent-gateway-sgp
source env.sh
./03-deploy-mcp.sh
source .env.runtime
</ql-code-block>

2. 배포된 MCP 서버의 `/tools` 엔드포인트를 직접 호출하여 4가지 뱅킹 도구의 JSON 스키마를 확인하고, Agent Gateway 서비스 에이전트(`AGW_SA`)에 `roles/run.servicesInvoker` 권한이 부여되었는지 확인합니다.

<ql-code-block language="bash">
ID_TOKEN="$(gcloud auth print-identity-token 2>/dev/null || true)"
curl -fsS -H "Authorization: Bearer ${ID_TOKEN}" "${MCP_URL}/tools" | python3 -m json.tool

gcloud run services get-iam-policy banking-mcp-server \
  --region="${LOCATION}" \
  --project="${PROJECT_ID}"
</ql-code-block>

아래 **Check my progress** 버튼을 클릭하여 작업 완료 여부를 확인합니다.
<ql-activity-tracking step=2>
    작업 3: Cloud Run 뱅킹 MCP 서버 배포 및 권한 설정 확인
</ql-activity-tracking>

## 작업 4. Agent Registry에 MCP 도구 및 Gemini Enterprise Global API 등록

`AGENT_TO_ANYWHERE` 모드로 동작하는 Agent Gateway는 기본 거부(Default Deny) 원칙을 따릅니다. 즉, Agent Registry에 등록되고 IAP Egress(`roles/iap.egressor`) 권한이 부여된 목적지로만 에이전트의 아웃바운드 통신이 허용됩니다. 이 작업에서는 뱅킹 MCP 서버를 Agent Registry에 등록하고, 에이전트가 `gemini-3.8-flash` 모델을 Global 엔드포인트(`https://aiplatform.googleapis.com`)로 호출할 수 있도록 필수 시스템 API 4종을 Allowlist에 등록합니다.

### MCP 도구 명세 추출 및 Agent Registry 서비스 등록

1. Cloud Run에 배포된 뱅킹 MCP 서버의 `/tools` 엔드포인트에서 도구 스키마를 추출하여 Agent Registry 규격의 `toolspec.json` 파일로 변환합니다.

<ql-code-block language="bash">
cd ~/agent-gateway-sgp
source env.sh
source .env.runtime

ID_TOKEN="$(gcloud auth print-identity-token 2>/dev/null || true)"
curl -fsS -H "Authorization: Bearer ${ID_TOKEN}" "${MCP_URL}/tools" | \
  python3 -c 'import sys, json; tools=json.load(sys.stdin); json.dump({"tools": tools}, open("toolspec.json", "w"))'
</ql-code-block>

2. 생성된 `toolspec.json`을 사용하여 Agent Registry에 `banking-mcp-server` 서비스를 등록합니다.

<ql-code-block language="bash">
gcloud alpha agent-registry services create banking-mcp-server \
  --project="${PROJECT_ID}" \
  --location="${LOCATION}" \
  --display-name="Banking MCP Server" \
  --interfaces=url="${MCP_URL}/mcp",protocolBinding=JSONRPC \
  --mcp-server-spec-type=tool-spec \
  --mcp-server-spec-content="toolspec.json" || true
</ql-code-block>

3. Agent Registry가 할당한 MCP 서버 리소스 ID(`MCP_SERVER_NAME`, 예: `agentregistry-xxxx...`)를 조회하여 `.env.runtime` 파일에 저장합니다.

<ql-code-block language="bash">
export MCP_SERVER_NAME="$(gcloud alpha agent-registry mcp-servers list \
  --project="${PROJECT_ID}" \
  --location="${LOCATION}" \
  --filter="displayName:'Banking MCP Server'" \
  --format="value(name.basename())" | head -n 1)"

echo "export MCP_SERVER_NAME=\"${MCP_SERVER_NAME}\"" >> ~/agent-gateway-sgp/.env.runtime
echo "Registered MCP Server ID: ${MCP_SERVER_NAME}"
</ql-code-block>

### Gemini Enterprise Global API 및 시스템 엔드포인트 4종 Allowlist 등록

1. 에이전트가 런타임에서 모델 추론(`https://aiplatform.googleapis.com`), 도구 조회(`https://agentregistry.googleapis.com`), 트레이싱(`https://telemetry.googleapis.com`), 로깅(`https://logging.googleapis.com`)을 수행할 수 있도록 4개 시스템 엔드포인트를 Agent Registry에 등록하고 `roles/iap.egressor` 권한을 바인딩합니다.

<ql-code-block language="bash">
ENDPOINTS=(
  "Gemini Enterprise Global API | https://aiplatform.googleapis.com"
  "Cloud Trace API | https://telemetry.googleapis.com"
  "Cloud Logging API | https://logging.googleapis.com"
  "Agent Registry API | https://agentregistry.googleapis.com"
)

for entry in "${ENDPOINTS[@]}"; do
  IFS="|" read -r name url <<< "$entry"
  name="$(echo "$name" | xargs)"
  url="$(echo "$url" | xargs)"
  service_id="$(echo "$name" | tr '[:upper:]' '[:lower:]' | tr -cd 'a-z0-9' | cut -c 1-40)"

  echo "Registering endpoint '${name}' (${url})..."
  res="$(gcloud alpha agent-registry services create "${service_id}" \
    --project="${PROJECT_ID}" \
    --location="${LOCATION}" \
    --display-name="${name}" \
    --endpoint-spec-type=no-spec \
    --interfaces=url="${url}",protocolBinding=JSONRPC \
    --format="value(registryResource)" 2>&1)" || true

  ep_id="$(echo "${res}" | grep -oE 'agentregistry-[0-9a-f-]+$' | head -n 1 || true)"
  if [[ -n "${ep_id}" ]]; then
    echo "Binding roles/iap.egressor on endpoint ${ep_id}..."
    gcloud alpha iap web add-iam-policy-binding \
      --resource-type=agent-registry \
      --endpoint="${ep_id}" \
      --region="${LOCATION}" \
      --project="${PROJECT_ID}" \
      --member="${AGW_SA}" \
      --role="roles/iap.egressor" \
      --quiet >/dev/null || true
  fi
done
</ql-code-block>

<ql-infobox><strong>팁:</strong> 위 과정은 <code>./04-register-mcp.sh</code> 스크립트로도 실행할 수 있습니다.</ql-infobox>

2. Agent Registry에 등록된 전체 서비스 목록(뱅킹 MCP 서버 및 4개 시스템 엔드포인트)을 확인합니다.

<ql-code-block language="bash">
gcloud alpha agent-registry services list \
  --project="${PROJECT_ID}" \
  --location="${LOCATION}" \
  --format="table(name.basename(),displayName)"
</ql-code-block>

## 작업 5. Gemini Enterprise Agent Runtime에 대화형 뱅킹 에이전트 비동기 배포

Gemini Enterprise Agent Runtime 컨테이너 빌드 및 배포는 백엔드에서 약 15~20분이 소요됩니다. 실습 시간을 절약하기 위해 에이전트 배포에 필요한 선행 리소스(`agent-egress` 게이트웨이 및 MCP 도구 등록)가 준비된 이 단계에서 `--no-wait` 플래그로 에이전트 배포를 백그라운드에서 먼저 시작한 뒤, 완료를 기다리지 않고 곧바로 작업 6과 작업 7을 진행합니다.

### 에이전트 코드의 Global 엔드포인트 및 모델 설정 확인

1. Cloud Shell에서 `conversational-banking/app/agent.py`의 구현을 확인합니다. 에이전트는 `GOOGLE_CLOUD_LOCATION="global"`을 설정하여 `gemini-3.8-flash` 모델 추론 요청이 Gemini Enterprise Global API(`https://aiplatform.googleapis.com`)로 전송되도록 하고, `AgentRegistry`를 통해 실습 리전에 등록된 뱅킹 MCP 도구 세트를 동적으로 불러옵니다.

<ql-code-block language="bash">
cd ~/agent-gateway-sgp
grep -n -C 8 "gemini-3.8-flash" conversational-banking/app/agent.py
</ql-code-block>

### TLS Inspection Root CA 인증서 추출 및 비동기 배포 실행

1. `agent-egress` 게이트웨이가 아웃바운드 HTTPS 페이로드를 복호화하여 SGP 정책 엔진으로 전달할 때 사용하는 Root CA 인증서를 추출하여 에이전트 빌드 디렉터리(`conversational-banking/agent-gateway-ca.crt`)에 저장합니다.

<ql-code-block language="bash">
cd ~/agent-gateway-sgp
source env.sh
source .env.runtime

gcloud network-services agent-gateways describe agent-egress \
  --location="${LOCATION}" \
  --project="${PROJECT_ID}" \
  --format="value(agentGatewayCard.rootCertificates[0])" > conversational-banking/agent-gateway-ca.crt
</ql-code-block>

2. `agents-cli deploy` 명령어에 `--agent-identity`, `--agent-gateway-egress`, `GOOGLE_CLOUD_LOCATION=global`, `MODEL=gemini-3.8-flash`, `--no-wait` 플래그를 지정하여 Gemini Enterprise Agent Runtime 배포를 시작하고, 생성된 에이전트 ID(`principal://...`)와 Reasoning Engine 서비스 에이전트에 Agent Registry 및 Cloud Run 호출 권한을 부여합니다.

<ql-code-block language="bash">
cd ~/agent-gateway-sgp
./05-deploy-agent.sh
</ql-code-block>

<ql-infobox><strong>팁:</strong> 배포 요청이 접수되면 백그라운드에서 컨테이너 빌드가 진행됩니다. 완료될 때까지 기다리지 말고 바로 작업 6으로 넘어가세요.</ql-infobox>

## 작업 6. SGP 정책 엔진 활성화, PSC 엔드포인트 및 프라이빗 Cloud DNS 구성

백그라운드에서 에이전트가 배포되는 동안 `agent-egress` 게이트웨이가 Google 관리형 SGP 정책 엔진과 사설망으로 통신할 수 있도록 Private Service Connect(PSC) 엔드포인트(`sgp-psc-endpoint`)와 프라이빗 Cloud DNS(`policy.internal.`)를 구성합니다.

### VPC 내부 고정 IP 확인 및 SGP 엔진 Service Attachment 조회

1. 실습 서브넷(`apex-subnet`) 내에 예약된 SGP PSC 엔드포인트용 내부 고정 IP(`sgp-psc-ip`) 주소를 확인합니다(없는 경우 자동으로 예약합니다).

<ql-code-block language="bash">
cd ~/agent-gateway-sgp
source env.sh

if ! gcloud compute addresses describe sgp-psc-ip --region="${LOCATION}" --project="${PROJECT_ID}" &>/dev/null; then
  gcloud compute addresses create sgp-psc-ip \
    --region="${LOCATION}" \
    --subnet="${SUBNET_NAME}" \
    --purpose=GCE_ENDPOINT \
    --project="${PROJECT_ID}"
fi

export PSC_IP="$(gcloud compute addresses describe sgp-psc-ip \
  --region="${LOCATION}" \
  --project="${PROJECT_ID}" \
  --format="value(address)")"
echo "PSC IP reserved: ${PSC_IP}"
</ql-code-block>

2. 실습 리전(`${LOCATION}`)에 활성화된 SGP 정책 엔진의 PSC Service Attachment URI를 조회합니다.

<ql-code-block language="bash">
SERVICE_ATTACHMENT="$(gcloud beta ai semantic-governance-policy-engine describe \
  --location="${LOCATION}" \
  --project="${PROJECT_ID}" \
  --format="value(pscServiceAttachment)" 2>/dev/null || true)"

if [[ -z "${SERVICE_ATTACHMENT}" ]]; then
  gcloud beta ai semantic-governance-policy-engine update \
    --location="${LOCATION}" \
    --project="${PROJECT_ID}" \
    --quiet
  SERVICE_ATTACHMENT="$(gcloud beta ai semantic-governance-policy-engine describe \
    --location="${LOCATION}" \
    --project="${PROJECT_ID}" \
    --format="value(pscServiceAttachment)" 2>/dev/null || true)"
fi

echo "Using SGP Service Attachment: ${SERVICE_ATTACHMENT}"
</ql-code-block>

### PSC 전달 규칙 및 프라이빗 Cloud DNS 구성

1. 예약된 내부 IP(`sgp-psc-ip`)와 SGP 엔진의 `SERVICE_ATTACHMENT`를 연결하는 PSC 전달 규칙(`sgp-psc-endpoint`)을 생성합니다.

<ql-code-block language="bash">
gcloud compute forwarding-rules create sgp-psc-endpoint \
  --region="${LOCATION}" \
  --network="${NETWORK_NAME}" \
  --address="sgp-psc-ip" \
  --target-service-attachment="${SERVICE_ATTACHMENT}" \
  --project="${PROJECT_ID}" || true
</ql-code-block>

2. 프라이빗 Cloud DNS 영역(`policy-engine-zone`)에 `agent-egress` 게이트웨이가 `policy.internal.` 도메인을 질의했을 때 PSC 엔드포인트 IP(`${PSC_IP}`)로 응답하도록 A 레코드를 생성합니다.

<ql-code-block language="bash">
gcloud dns record-sets create policy.internal. \
  --zone=policy-engine-zone \
  --type=A \
  --ttl=300 \
  --rrdatas="${PSC_IP}" \
  --project="${PROJECT_ID}" || true
</ql-code-block>

<ql-infobox><strong>팁:</strong> 위 과정은 <code>./06-setup-sgp-networking.sh</code> 스크립트로도 실행할 수 있습니다.</ql-infobox>

3. PSC 엔드포인트 연결 상태가 `ACCEPTED`인지 확인합니다.

<ql-code-block language="bash">
gcloud compute forwarding-rules describe sgp-psc-endpoint \
  --region="${LOCATION}" \
  --project="${PROJECT_ID}" \
  --format="table(name,IPAddress,pscConnectionStatus)"
</ql-code-block>

아래 **Check my progress** 버튼을 클릭하여 작업 완료 여부를 확인합니다.
<ql-activity-tracking step=3>
    작업 6: SGP 전용 Private Service Connect 엔드포인트 및 Cloud DNS 구성 확인
</ql-activity-tracking>

## 작업 7. 인가 확장(AuthzExtension), 인가 정책 및 자연어 SGP 정책 생성

이 작업에서는 `agent-egress` 게이트웨이를 통과하는 도구 호출 페이로드를 PSC 터널(`policy.internal`) 너머의 SGP 정책 엔진으로 전달하기 위한 Service Extensions 인가 확장(`sgp-authzextension`)과 콘텐츠 인가 정책(`agent-egress-sgp-authzpolicy`, `CONTENT_AUTHZ`)을 구성합니다. 이어서 작업 5에서 비동기로 시작한 에이전트의 Agent Identity(`AGENT_ID`) 등록을 확인한 뒤, 1회 100만 원(`amount <= 1000.0`) 초과 이체를 차단하는 시맨틱 거버넌스 정책(`high-value-limit`)을 생성합니다.

### SGP 인가 확장 및 콘텐츠 인가 정책 바인딩

1. `failOpen: false`(장애 시 차단 원칙)로 설정된 SGP 인가 확장(`sgp-authzextension`)을 등록합니다.

<ql-code-block language="bash">
cd ~/agent-gateway-sgp
source env.sh
source .env.runtime

ACCESS_TOKEN="$(gcloud auth print-access-token)"
curl -fsS -X POST \
  "https://networkservices.googleapis.com/v1beta1/projects/${PROJECT_ID}/locations/${LOCATION}/authzExtensions?authzExtensionId=sgp-authzextension" \
  -H "Authorization: Bearer ${ACCESS_TOKEN}" \
  -H "Content-Type: application/json" \
  -d '{
    "service": "policy.internal",
    "authority": "policy.internal",
    "failOpen": false,
    "loadBalancingScheme": "LOAD_BALANCING_SCHEME_UNSPECIFIED"
  }' || echo "Note: Authz extension might already exist."
</ql-code-block>

2. `agent-egress` 게이트웨이를 대상으로 비-gRPC 콘텐츠 생성 및 MCP 도구 호출을 `sgp-authzextension`으로 위임하는 `agent-egress-sgp-authzpolicy.yaml` 매니페스트를 작성하고 임포트합니다.

<ql-code-block language="bash">
cat > agent-egress-sgp-authzpolicy.yaml << EOF
name: projects/${PROJECT_ID}/locations/${LOCATION}/authzPolicies/agent-egress-sgp-authzpolicy
target:
  loadBalancingScheme: LOAD_BALANCING_SCHEME_UNSPECIFIED
  resources:
    - "projects/${PROJECT_NUM}/locations/${LOCATION}/agentGateways/agent-egress"
httpRules:
  - to:
      operations:
        - paths:
            - prefix: "/"
    when: '!request.headers["content-type"].startsWith("application/grpc") && (request.path.endsWith(":generateContent") || request.path.endsWith(":streamGenerateContent"))'
action: CUSTOM
policyProfile: CONTENT_AUTHZ
customProvider:
  authzExtension:
    resources:
      - "projects/${PROJECT_NUM}/locations/${LOCATION}/authzExtensions/sgp-authzextension"
EOF

gcloud beta network-security authz-policies import agent-egress-sgp-authzpolicy \
  --source=agent-egress-sgp-authzpolicy.yaml \
  --location="${LOCATION}" \
  --project="${PROJECT_ID}"
</ql-code-block>

### 에이전트 등록 완료 확인 및 시맨틱 거버넌스 정책 생성

1. 작업 5에서 백그라운드로 시작한 `conversational-banking` 에이전트가 Agent Registry에 등록될 때까지 20초 간격으로 확인하여 `AGENT_ID`를 조회합니다.

<ql-code-block language="bash">
export AGENT_ID="$(gcloud alpha agent-registry agents list \
  --project="${PROJECT_ID}" \
  --location="${LOCATION}" \
  --filter="displayName:'conversational-banking'" \
  --format="value(name.basename())" 2>/dev/null | head -n 1 || true)"

while [[ -z "${AGENT_ID}" ]]; do
  echo "Waiting for background Agent Runtime deployment to register in Agent Registry... (20s)"
  sleep 20
  export AGENT_ID="$(gcloud alpha agent-registry agents list \
    --project="${PROJECT_ID}" \
    --location="${LOCATION}" \
    --filter="displayName:'conversational-banking'" \
    --format="value(name.basename())" 2>/dev/null | head -n 1 || true)"
done

echo "export AGENT_ID=\"${AGENT_ID}\"" >> ~/agent-gateway-sgp/.env.runtime
echo "Registered Agent ID: ${AGENT_ID}"
</ql-code-block>

2. 조회된 `AGENT_ID`와 `MCP_SERVER_NAME`, 그리고 ADK 런타임 도구 식별자인 `Banking_MCP_Server_transfer_to_phone`을 지정하여 100만 원(`USD 1000` / `amount: 1000`) 초과 송금을 차단하는 시맨틱 거버넌스 정책(`high-value-limit`)을 생성합니다.

<ql-code-block language="bash">
TOOL_NAME="Banking_MCP_Server_transfer_to_phone"

gcloud beta ai semantic-governance-policies create high-value-limit \
  --project="${PROJECT_ID}" \
  --location="${LOCATION}" \
  --display-name="High Value Transfer Limit" \
  --agent="projects/${PROJECT_ID}/locations/${LOCATION}/agents/${AGENT_ID}" \
  --mcp-tools="mcp-server=projects/${PROJECT_ID}/locations/${LOCATION}/mcpServers/${MCP_SERVER_NAME},tools=${TOOL_NAME}" \
  --natural-language-constraint="Block any transfer value exceeding USD 1000." || \
gcloud beta ai semantic-governance-policies update high-value-limit \
  --project="${PROJECT_ID}" \
  --location="${LOCATION}" \
  --agent="projects/${PROJECT_ID}/locations/${LOCATION}/agents/${AGENT_ID}" \
  --mcp-tools="mcp-server=projects/${PROJECT_ID}/locations/${LOCATION}/mcpServers/${MCP_SERVER_NAME},tools=${TOOL_NAME}" \
  --natural-language-constraint="Block any transfer value exceeding USD 1000."
</ql-code-block>

<ql-infobox><strong>팁:</strong> 위 과정(에이전트 대기 폴링 및 정책 생성/업데이트 포함)은 <code>./07-create-sgp-policy.sh</code> 스크립트로도 실행할 수 있습니다.</ql-infobox>

3. 생성된 `high-value-limit` 시맨틱 거버넌스 정책의 상세 설정을 확인합니다.

<ql-code-block language="bash">
gcloud beta ai semantic-governance-policies describe high-value-limit \
  --location="${LOCATION}" \
  --project="${PROJECT_ID}"
</ql-code-block>

<ql-true-false-probe stem="sgp-authzextension 구성 시 failOpen을 false로 설정하면, SGP 정책 엔진에 장애가 발생하더라도 인가되지 않은 도구 호출이 우회 통과되지 않도록 차단(Fail-Closed)됩니다."
                     answer="true">
</ql-true-false-probe>

## 작업 8. 3-Turn 금융 거버넌스 시나리오 검증 및 Cloud Logging 감사 로그 확인

구성이 완료되면 Cloud Shell에서 3-Turn 시나리오 검증 스크립트(`08-test.sh`)를 실행하여 계좌 조회(Turn 1)와 5만 원 소액 송금(Turn 2)은 정상 허용(`ALLOW`)되고, 200만 원 고액 송금(Turn 3)은 네트워크 경계의 Agent Gateway와 SGP 엔진에 의해 차단(`DENY`)되는지 확인합니다.

### Cloud Shell에서 3-Turn 시나리오 테스트 실행

1. Cloud Shell에서 아래 명령어를 실행하여 Gemini Enterprise Agent Runtime에 배포된 `conversational-banking` 에이전트를 대상으로 3-Turn 시나리오 테스트를 수행합니다.

<ql-code-block language="bash">
cd ~/agent-gateway-sgp
./08-test.sh
</ql-code-block>

2. 터미널 출력에서 각 Turn의 도구 호출 결과와 SGP 판정을 확인합니다.
   * **Turn 1** (`I am customer CUST005`): `get_account` 도구가 호출되어 고객(Alice Smith / 김민준)의 현재 잔액 1,000만 원(`$10,000.00`)이 조회됩니다.
   * **Turn 2** (`transfer 50 to 555-0001`): 1회 한도(100만 원 / `$1,000`) 이하인 5만 원(`amount: 50`) 송금 요청에 대해 SGP가 `ALLOW`로 판정하여 이체가 완료되고 잔액이 995만 원(`$9,950.00`)으로 변경됩니다.
   * **Turn 3** (`transfer 2000 to 555-0002`): 1회 한도를 초과하는 200만 원(`amount: 2000`) 송금 요청에 대해 SGP가 `DENY`로 판정하여 Cloud Run 백엔드에 도달하기 전에 Agent Gateway에서 차단됩니다.

<ql-code-block output>
[Turn 1 - Identify Customer]
Prompt: I am customer CUST005
Agent Response:
Hello Alice Smith! I have retrieved your account (ACT-1005). Your current balance is $10,000.00. How can I help you today?
Turn 1 PASSED (Customer identified & balance retrieved)

[Turn 2 - Allowed Transfer (< $1,000 USD)]
Prompt: transfer 50 to 555-0001
Agent Response:
Your transfer of $50.00 to Bob Jones (555-0001) has been completed successfully. Your new balance is $9,950.00.
Turn 2 PASSED (Under-limit transfer of $50 allowed and processed)

[Turn 3 - Blocked Transfer (> $1,000 USD by SGP)]
Prompt: transfer 2000 to 555-0002
Agent Response:
I'm sorry, I cannot complete the transfer of $2,000.00 to 555-0002 because it exceeds the maximum allowed limit of $1,000.00 per transaction enforced by our security policy.
Turn 3 PASSED (Over-limit transfer of $2000 blocked by SGP)
</ql-code-block>

### Cloud Logging에서 SGP 감사 로그 조회

1. Cloud Shell에서 아래 명령어를 실행하여 SGP 정책 엔진이 남긴 감사 로그(`ALLOW` 및 `DENY` 판정 결과와 판단 근거 `rationale`)를 확인합니다.

<ql-code-block language="bash">
cd ~/agent-gateway-sgp
source env.sh

gcloud logging read \
  "logName=\"projects/${PROJECT_ID}/logs/semantic-governance-policy\"" \
  --project="${PROJECT_ID}" \
  --limit=5 \
  --format=json
</ql-code-block>

아래 **Check my progress** 버튼을 클릭하여 작업 완료 여부를 확인합니다.
<ql-activity-tracking step=4>
    작업 7~8: 시맨틱 거버넌스 정책(high-value-limit) 생성 및 3-Turn 시나리오 검증 확인
</ql-activity-tracking>

## 작업 9. 리소스 정리 (선택 사항)

개인 프로젝트에서 실습을 재현한 경우 불필요한 과금을 방지하기 위해 생성한 SGP 정책, Cloud Run 서비스, Agent Gateway, DNS 영역 및 PSC 엔드포인트를 정리할 수 있습니다.

<ql-warningbox><strong>주의:</strong> 모든 채점 단계(<strong>Check my progress</strong>)의 점수 확인을 완료한 뒤에만 아래 정리 스크립트를 실행하세요. Qwiklabs 임시 프로젝트 환경에서는 실습 종료(<strong>End Lab</strong>) 시 프로젝트가 자동으로 삭제됩니다.</ql-warningbox>

### 클라우드 리소스 삭제

* Cloud Shell에서 아래 스크립트를 실행하여 생성된 리소스를 역순으로 삭제합니다.

<ql-code-block language="bash">
cd ~/agent-gateway-sgp
./99-cleanup.sh
</ql-code-block>

## 실습 완료

이 실습에서는 Gemini Enterprise Agent Runtime(`gemini-3.8-flash`, Global 엔드포인트)에서 실행되는 자율형 AI 에이전트의 아웃바운드 도구 호출을 Google Cloud Agent Gateway(`agent-egress`)와 시맨틱 거버넌스 정책(SGP)으로 통제하는 보안 거버넌스 아키텍처를 구현했습니다.

* Agent Registry 기반의 동적 도구 조회 및 시스템 엔드포인트 Allowlist 통제 구성
* Private Service Connect(PSC)와 프라이빗 Cloud DNS(`policy.internal.`)를 통한 SGP 정책 엔진 사설망 연동
* 자연어 비즈니스 제약 조건(`high-value-limit`) 정의 및 3-Turn 금융 거래 시나리오(소액 이체 허용, 고액 이체 차단) 검증

### 참고 자료

* [Gemini Enterprise Agent Platform - Agent Gateway 개요](https://docs.cloud.google.com/gemini-enterprise-agent-platform/govern/gateways/agent-gateway-overview)
* [Agent Registry를 활용한 에이전트 및 MCP 도구 카탈로그 관리](https://docs.cloud.google.com/gemini-enterprise-agent-platform/govern/agent-registry)
* [Agent Identity 및 IAP 기반 권한 제어](https://docs.cloud.google.com/gemini-enterprise-agent-platform/govern/agent-identity-overview)
* [Google Agent Development Kit (ADK) 공식 문서](https://google.github.io/adk-docs/)

### 실습 종료하기

실습을 모두 마쳤다면 좌측 상단의 **End Lab** 버튼을 클릭한 뒤 **Submit**을 눌러 실습을 종료합니다. 실습이 종료되면 사용한 Google Cloud 프로젝트와 리소스가 자동으로 정리됩니다.

![[/fragments/copyright]]
