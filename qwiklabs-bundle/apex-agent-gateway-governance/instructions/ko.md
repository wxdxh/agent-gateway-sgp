# Gemini Enterprise Agent Platform과 Agent Gateway(IAP·Model Armor)를 활용한 에이전트 워크로드 거버넌스

## 개요

엔터프라이즈 환경에서 자율형 AI 에이전트가 실제 비즈니스 가치를 창출하려면 내부 문서 관리 시스템, 외부 금융 검증 API, 사내 이메일 서버 등 다양한 엔터프라이즈 시스템과 연결되어야 합니다. Model Context Protocol (MCP) 은 에이전트가 이러한 외부 도구(Tool)를 표준화된 JSON-RPC 인터페이스로 호출할 수 있게 해주지만, 동시에 기업 보안팀과 플랫폼 엔지니어에게 다음과 같은 세 가지 핵심 거버넌스 과제를 안겨줍니다.

1. **세분화된 도구(Tool) 단위 접근 제어 부재**: 특정 MCP 서버에 대한 네트워크 연결 및 호출 권한(`roles/run.invoker`)을 부여하면, 에이전트가 해당 서버의 안전한 조회 도구(`search_emails`, `read_email`)뿐만 아니라 외부로 민감 정보를 유출하거나 상태를 변경하는 고위험 도구(`send_email`)까지 무제한으로 호출할 수 있습니다.
2. **민감 개인정보(PII)의 LLM 컨텍스트 유입 위험**: 레거시 DB나 문서 시스템이 반환하는 원본 응답에 한국 주민등록번호(`KOREA_RRN`) 나 미국 사회보장번호(`US_SOCIAL_SECURITY_NUMBER`) 같은 고위험 개인정보가 포함되어 있으면, 해당 데이터가 그대로 LLM 프롬프트 컨텍스트와 대화 로그에 노출됩니다.
3. **에이전트-도구 간 블랙박스 통신 및 관측성(Observability) 부족**: 에이전트가 어떤 MCP 도구를 얼마나 호출하는지, 지연 시간(Latency)이 어디서 발생하는지, 어떤 보안 정책에 의해 차단 또는 마스킹되었는지 중앙에서 추적하기 어렵습니다.

이 실습에서는 에이펙스 금융그룹(Apex Financial Group)의 주택담보대출 자동 심사 에이전트(`mortgage-agent`) 시나리오를 바탕으로, 백엔드 MCP 서버의 비즈니스 로직을 수정하지 않고도 Google Cloud Agent Gateway와 Service Extensions(IAP 및 Model Armor + Cloud DLP) 를 결합하여 중앙 집중식 보안 거버넌스와 통합 관측성을 구현합니다.

![에이펙스 금융그룹 Agent Gateway 거버넌스 전체 아키텍처](img/00-overall-architecture.png)

---

### 실습 시나리오: 에이펙스 금융그룹 주택담보대출 심사 에이전트

에이펙스 금융그룹의 대출 심사관(Underwriter)은 공동 신청자인 김민준(Minjun Kim) · 이서연(Seoyeon Lee) 부부의 2026년 신규 주택담보대출 적격 여부를 심사하기 위해 Vertex AI Agent Engine에서 실행되는 `mortgage-agent` 를 사용합니다. 에이전트는 심사를 수행하기 위해 다음 3개의 백엔드 MCP 서버와 통신합니다.

| MCP 서버 이름 | 비즈니스 역할 | 노출된 MCP 도구 (Tools) | Agent Gateway 배포 토폴로지 | 적용되는 거버넌스 정책 |
| :--- | :--- | :--- | :--- | :--- |
| `legacy-dms` | 레거시 문서 관리 시스템 (2023·2024 소득금액증명원 조회) | `search_tax_returns`, `get_document_metadata` | 클라이언트 사이드 (`agent-egress`)<br>`AGENT_TO_ANYWHERE` | Model Armor + Cloud DLP (`CONTENT_AUTHZ`):<br>응답 내 주민등록번호(`850315-1234566` ➔ `[KOREA_RRN]`) 및 SSN(`323-45-6789` ➔ `[US_SOCIAL_SECURITY_NUMBER]`) 자동 마스킹 |
| `income-verification` | 외부 소득 및 재직 검증 API (2026년 DTI 산출) | `verify_income` | 클라이언트 사이드 (`agent-egress`)<br>`AGENT_TO_ANYWHERE` | Model Armor + Cloud DLP (`CONTENT_AUTHZ`):<br>외부 API 요청·응답 내 주민등록번호(`[KOREA_RRN]`) 및 SSN(`[US_SOCIAL_SECURITY_NUMBER]`) 양방향 마스킹 |
| `corporate-email` | 사내 이메일 및 심사 지침 서버 (2026년 DTI 한도 45% 공지) | `search_emails`, `read_email`, `send_email` | 서버 사이드 (`cloud-run`)<br>`self_managed` 인그레스 보호 | IAP + CEL (`REQUEST_AUTHZ`):<br>`search_emails`·`read_email` 조회는 허용하되, `send_email` 도구 호출은 차단 (`DRY_RUN` 검증 후 `ENFORCED` 전환) |

---

### 핵심 아키텍처 개념

#### 1. Agent Gateway의 두 가지 배포 토폴로지: 클라이언트 사이드(`agent-egress`) vs 서버 사이드(`cloud-run`)
* **클라이언트 사이드 게이트웨이** (`google_managed.governed_access_path = "AGENT_TO_ANYWHERE"`): 에이전트의 아웃바운드(Egress) 경로에 위치하는 정방향 프록시(Forward Proxy)입니다. 타사 SaaS API나 직접 제어할 수 없는 레거시 시스템(`legacy-dms`, `income-verification`)으로 나가는 에이전트 트래픽을 가로채어 감사 및 DLP 마스킹을 수행합니다.
* **서버 사이드 게이트웨이** (`self_managed.resource_uri`): 기업 내부의 Cloud Run MCP 워크로드(`corporate-email`) 앞단에 위치하는 역방향 프록시(Reverse Proxy)입니다. 모든 인바운드 MCP 요청에 대해 호출자 ID 검증과 도구 단위 인가(IAP CEL)를 강제합니다.

![네트워킹 모드 비교: 기본 퍼블릭 인그레스 vs 프라이빗 네트워킹](img/01-networking-modes.png)

#### 2. Service Extensions 기반 이중 보안 통제: IAP(`REQUEST_AUTHZ`) & Model Armor(`CONTENT_AUTHZ`)
Agent Gateway는 Envoy 기반 데이터 플레인 위에서 두 가지 실행 단계(Phase)로 Google Cloud 보안 서비스를 체이닝합니다.
* **`REQUEST_AUTHZ` 단계 — Identity-Aware Proxy (IAP) + CEL**: MCP JSON-RPC 요청 헤더와 본문(`request.mcp.method`, `request.mcp.tool.name`)을 분석하여 특정 도구 호출을 허용하거나 거부합니다. 또한 `DRY_RUN` 모드를 지원하므로 운영 트래픽을 중단시키지 않고 정책 위반 여부를 먼저 감사 로그로 검증한 뒤 강제 적용(`ENFORCED`) 모드로 안전하게 전환할 수 있습니다.
* **`CONTENT_AUTHZ` 단계 — Model Armor + Cloud DLP** (Sensitive Data Protection): MCP 요청 및 응답 페이로드(`structuredContent`)를 실시간 스캔하여 프롬프트 인젝션 공격을 차단하고, 한국 주민등록번호(`KOREA_RRN`)와 미국 사회보장번호(`US_SOCIAL_SECURITY_NUMBER`)를 `[KOREA_RRN]`, `[US_SOCIAL_SECURITY_NUMBER]` 토큰으로 치환(Redaction)합니다.

![IAP CEL 및 Model Armor DLP 이중 보안 통제 흐름](img/02-iap-cel-model-armor.png)

---

### 학습 목표

이 실습을 완료하면 다음 작업을 수행할 수 있습니다.

* Skaffold와 Cloud Build를 사용하여 3종의 FastMCP 기반 백엔드 서버(`legacy-dms`, `income-verification`, `corporate-email`) 컨테이너를 빌드하고 Artifact Registry에 배포합니다.
* Terraform을 사용하여 클라이언트 사이드(`agent-egress`) 및 서버 사이드(`cloud-run`) Agent Gateway 3종과 Cloud Monitoring 커스텀 대시보드를 프로비저닝합니다.
* Cloud DLP `InspectTemplate` / `DeidentifyTemplate`(`KOREA_RRN`, `US_SOCIAL_SECURITY_NUMBER`)과 Model Armor 템플릿을 구성하여 MCP 응답 내 민감 개인정보를 실시간 마스킹합니다.
* IAP의 CEL(Common Expression Language) 정책을 `DRY_RUN` 모드로 먼저 배포하여 테스트한 뒤, `ENFORCED` 모드로 전환하여 무단 외부 이메일 발송(`send_email`)을 실시간 차단합니다.
* Vertex AI Agent Engine Playground, Cloud Monitoring 대시보드, Cloud Trace, Cloud Logging을 활용해 에이전트 거버넌스 동작을 엔드투엔드로 검증합니다.

---

## 설정 및 요구사항

### 실습 시작 전 확인사항

1. Qwiklabs 화면 좌측 상단의 Start Lab(실습 시작) 버튼을 클릭합니다.
2. 실습 환경이 준비되면 좌측 패널에 표시되는 Project ID, Region, Username, Password 정보를 확인합니다.
3. Open Google Cloud console 버튼을 클릭하여 시크릿 창(Incognito)에서 Google Cloud 콘솔에 로그인합니다.
4. 콘솔 우측 상단의 터미널 아이콘(Activate Cloud Shell)을 클릭하여 Cloud Shell을 엽니다.

> **참고**: Qwiklabs 시작 스크립트(Startup Script)가 실습에 필요한 Google Cloud API 20종과 기본 서비스 에이전트(Vertex AI, Cloud DLP)를 백그라운드에서 사전 활성화합니다.

---

## 작업 1. 실습 환경 변수 설정 및 소스 저장소 클론

Cloud Shell에서 프로젝트 환경 변수를 설정하고, 한국형 주택담보대출 심사 시나리오가 적용된 실습 저장소를 클론합니다.

### 1. 환경 변수 초기화 및 인증 확인

Cloud Shell 터미널에서 다음 명령어를 실행합니다.

```bash
export PROJECT_ID=$(gcloud config get-value project)
export PROJECT_NUMBER=$(gcloud projects describe "${PROJECT_ID}" --format="value(projectNumber)")
export ORG_ID=$(gcloud projects get-ancestors "${PROJECT_ID}" --format='value(id)' | tail -n 1)
if [ "${ORG_ID}" = "${PROJECT_ID}" ] || [ "${ORG_ID}" = "${PROJECT_NUMBER}" ]; then
  export ORG_ID=""
fi
export REGION="us-central1"

gcloud config set project "${PROJECT_ID}"
gcloud config set compute/region "${REGION}"

echo "PROJECT_ID     : ${PROJECT_ID}"
echo "PROJECT_NUMBER : ${PROJECT_NUMBER}"
echo "ORG_ID         : ${ORG_ID:-'(No Organization - Project Fallback Mode)'}"
echo "REGION         : ${REGION}"
```

### 2. 실습 소스 코드 저장소 클론

다음 명령어를 실행하여 실습 저장소를 클론하고 디렉터리 구조를 확인합니다.

```bash
cd ~
rm -rf ~/agent-gateway-governance
git clone https://github.com/wxdxh/agent-gateway-governance.git ~/agent-gateway-governance 2>/dev/null || \
  git clone -b governance https://github.com/wxdxh/agent-gateway-sgp.git ~/agent-gateway-governance

cd ~/agent-gateway-governance
ls -la
```

저장소는 다음과 같은 핵심 디렉터리로 구성되어 있습니다.

* `src/legacy-dms/`: 소득금액증명원 검색 및 문서 메타데이터를 제공하는 FastMCP 서버 (주민등록번호 `850315-1234566` 및 SSN 포함)
* `src/income-verification-api/`: 신청자 소득 검증 및 2026년 DTI 비율을 계산하는 FastMCP 서버
* `src/corporate-email/`: 사내 언더라이팅 지침 이메일 검색·열람(`search_emails`, `read_email`) 및 이메일 발송(`send_email`) 도구를 가진 FastMCP 서버
* `src/mortgage-agent/`: Google ADK 기반 주택담보대출 심사 에이전트 및 배포 스크립트(`deploy_agent.py`)
* `terraform/`: Cloud Run, Agent Gateway, IAP, Model Armor/DLP, Vertex AI Agent Engine, Cloud Monitoring 대시보드를 배포하는 Terraform 모듈
* `scripts/grant_agent_mcp_egress.sh`: 배포된 에이전트 고유 ID(Agent Identity)에 Agent Registry 엔드포인트 및 MCP 서버별 `roles/iap.egressor` 권한(조건부 CEL 정책 포함)을 부여하는 스크립트

---

## 작업 2. Agent Gateway, IAP(`DRY_RUN`) 및 Model Armor(`KOREA_RRN`/`SSN`) Terraform 프로비저닝

먼저 Agent Gateway의 Model Armor(`CONTENT_AUTHZ`)가 MCP 도구 응답에서 민감 정보를 마스킹할 수 있도록 FastMCP 서버의 응답 구조를 점검한 뒤, Terraform을 사용하여 VPC, Artifact Registry(`gateway-docker`), 플레이스홀더 Cloud Run 서비스, Agent Gateway(`agent-gateway`), IAP AuthzExtension(`DRY_RUN` 모드), Model Armor 및 Cloud DLP 템플릿(`KOREA_RRN` 및 `US_SOCIAL_SECURITY_NUMBER`), 그리고 Agent Registry 엔드포인트를 프로비저닝합니다.

### 1. FastMCP의 `structuredContent` 반환 구조 확인

다음 명령어로 `src/legacy-dms/server.py`의 도구 반환 코드를 확인합니다.

```bash
sed -n '95,145p' ~/agent-gateway-governance/src/legacy-dms/server.py
```

* FastMCP는 기본적으로 파이썬 딕셔너리 반환값을 직렬화할 때 일반 텍스트 블록(`content`)과 구조화된 JSON 블록(`structuredContent`)을 동시에 생성합니다.
* 현재 Agent Gateway의 Model Armor 연동은 MCP 응답의 `structuredContent` 필드만 검사하고 마스킹(Redaction)합니다. 만약 `content` 배열에 원본 문자열이 남아 있으면 마스킹되지 않은 주민등록번호나 SSN이 에이전트로 유출될 수 있으므로, 모든 MCP 도구는 반드시 `ToolResult(content=[], structured_content=...)` 형태로 반환하도록 설계되어 있습니다.

### 2. Terraform 거버넌스 구성 파일 점검

배포 전에 `terraform/example.tfvars`에서 각 보안 계층이 어떻게 정의되어 있는지 확인합니다.

```bash
cat ~/agent-gateway-governance/terraform/example.tfvars
```

주요 구성 포인트는 다음과 같습니다.

1. `model_armor_pii_types`: `["US_SOCIAL_SECURITY_NUMBER", "KOREA_RRN"]`이 설정되어 있어, Cloud DLP(`agw-ssn-inspect-template` 및 `agw-ssn-redaction-template`)가 미국 사회보장번호(`323-45-6789`)와 한국 주민등록번호(`850315-1234566`, `870822-2345673`)를 모두 탐지하고 각각 `[US_SOCIAL_SECURITY_NUMBER]`, `[KOREA_RRN]`으로 마스킹합니다.
2. `agent_gateway_iap_iam_enforcement_mode = "DRY_RUN"`: Agent Gateway의 IAP 확장(`agent-gateway-iap-authz`)이 초기에는 `DRY_RUN` 모드로 배포됩니다. 즉, 첫 테스트에서는 권한이 없는 `send_email` 호출이 실제로 차단되지 않고 감사 로그에만 기록됩니다.
3. `enable_cloud_run_private_networking = false`: 빠른 실습을 위해 퍼블릭 `*.run.app` 인그레스와 IAM OIDC 인증을 사용하며, 엔터프라이즈 폐쇄망 환경에서는 `true`로 설정하여 내부 애플리케이션 부하 분산기(ILB)와 프라이빗 Cloud DNS 경로로 전환할 수 있습니다.

### 3. Terraform 상태 버킷 생성 및 전체 인프라 프로비저닝

다음 명령어로 GCS 상태 버킷을 생성하고 `example.tfvars`를 기반으로 `terraform/terraform.tfvars`를 구성한 뒤 `terraform apply`를 실행합니다.

```bash
cd ~/agent-gateway-governance

gcloud storage buckets create "gs://${PROJECT_ID}-tfstate" \
  --location="${REGION}" \
  --uniform-bucket-level-access 2>/dev/null || true

cat <<EOF > terraform/backend.conf
bucket = "${PROJECT_ID}-tfstate"
prefix = "terraform/state"
EOF

cp terraform/example.tfvars terraform/terraform.tfvars
USER_EMAIL=$(gcloud config get-value account)

sed -i "s|YOUR_PROJECT_ID|${PROJECT_ID}|g" terraform/terraform.tfvars
sed -i "s|YOUR_ORG_ID|${ORG_ID}|g" terraform/terraform.tfvars
sed -i "s|YOUR_ADMIN_EMAIL|${USER_EMAIL}|g" terraform/terraform.tfvars

terraform -chdir=terraform init -backend-config=backend.conf
terraform -chdir=terraform apply -auto-approve
```

> **참고**: VPC, Artifact Registry(`gateway-docker`), Cloud DLP 템플릿, Model Armor 템플릿(`agw-request-template`, `agw-response-template`), 플레이스홀더 Cloud Run 서비스, Agent Gateway(`agent-gateway`), IAP/Model Armor AuthzPolicy 및 Agent Registry 등록이 완료되는 데 약 3~5분이 소요됩니다.

### 4. Terraform 출력값(Outputs) 확인

프로비저닝이 완료되면 생성된 리소스 출력값을 확인합니다.

```bash
terraform -chdir=terraform output
```

<ql-activity-tracking step=1>
Agent Gateway, IAP(DRY_RUN) 및 Model Armor 프로비저닝 확인하기
</ql-activity-tracking>

---

## 작업 3. Skaffold를 이용한 3종 주택담보대출 MCP 서버 빌드 및 Cloud Run 배포

Terraform은 Agent Registry에 서비스 URL을 선등록하기 위해 3개의 플레이스홀더 Cloud Run 서비스(`legacy-dms`, `income-verification`, `corporate-email`)를 먼저 생성했습니다. 이제 Skaffold 및 Cloud Run 매니페스트 템플릿을 렌더링하고 `skaffold run`을 실행하여 실제 FastMCP 서버 컨테이너를 빌드 및 배포합니다.

### 1. Cloud Build / Cloud Run 배포를 위한 서비스 계정 사용자 권한 부여

Skaffold가 Cloud Run 서비스를 배포할 수 있도록 기본 Compute Engine 서비스 계정에 대한 `roles/iam.serviceAccountUser` 역할을 현재 사용자 계정에 부여합니다.

```bash
cd ~/agent-gateway-governance
USER_EMAIL=$(gcloud config get-value account)

gcloud iam service-accounts add-iam-policy-binding \
  "${PROJECT_NUMBER}-compute@developer.gserviceaccount.com" \
  --project="${PROJECT_ID}" \
  --member="user:${USER_EMAIL}" \
  --role="roles/iam.serviceAccountUser"
```

### 2. 매니페스트 템플릿 렌더링 및 Skaffold 빌드·배포 실행

`.tmpl` 템플릿 파일들로부터 `skaffold.yaml`과 `cloudrun/*.yaml` 매니페스트를 생성한 후 `skaffold run`을 실행합니다.

```bash
cd ~/agent-gateway-governance
export MCP_INGRESS="all"

envsubst '${PROJECT_ID} ${REGION} ${MCP_INGRESS}' < skaffold.yaml.tmpl > skaffold.yaml
for tmpl in cloudrun/*.yaml.tmpl; do
  envsubst '${PROJECT_ID} ${REGION} ${MCP_INGRESS}' < "${tmpl}" > "${tmpl%.tmpl}"
done

skaffold run
```

### 3. 빌드된 이미지 및 Cloud Run 서비스 확인

`gateway-docker` 저장소에 3개의 컨테이너 이미지가 등록되고 Cloud Run 서비스가 정상 업데이트되었는지 확인합니다.

```bash
gcloud artifacts docker images list "${REGION}-docker.pkg.dev/${PROJECT_ID}/gateway-docker" --include-tags
gcloud run services list --region="${REGION}"
```

<ql-activity-tracking step=2>
Skaffold 이미지 빌드 및 Cloud Run MCP 서버 배포 확인하기
</ql-activity-tracking>

---

## 작업 4. 주택담보대출 심사 에이전트(`mortgage-agent`) 배포 및 조건부 IAP CEL Egress 설정

이제 Google ADK로 작성된 `mortgage-agent`를 **에이전트 고유 ID(`--enable-agent-identity`)** 및 **Agent Gateway 연동(`--agent-gateway`)** 옵션과 함께 Vertex AI Agent Engine에 배포하고, `scripts/grant_agent_mcp_egress.sh`를 사용하여 MCP 서버별 세분화된 IAP 도구 인가 정책을 바인딩합니다.

### 1. ADK 에이전트 및 동적 MCP 디스커버리 코드 확인

`src/mortgage-agent/agent/agent.py`에서 에이전트가 Agent Registry로부터 MCP 서버를 동적으로 검색하고 인증하는 방식을 확인합니다.

```bash
sed -n '1,95p' ~/agent-gateway-governance/src/mortgage-agent/agent/agent.py
```

* 에이전트는 시작 시 **Agent Registry(`agentregistry.googleapis.com`)**를 조회하여 `legacy-dms`, `income-verification`, `corporate-email`의 MCP 엔드포인트 URL을 동적으로 가져옵니다.
* `--agent-gateway` 옵션으로 배포되므로 에이전트에서 나가는 모든 HTTP/MCP 호출은 자동으로 **`agent-gateway`(`AGENT_TO_ANYWHERE` 정방향 프록시)**를 경유하며, 이 지점에서 IAP(`REQUEST_AUTHZ`)와 Model Armor(`CONTENT_AUTHZ`)가 실행됩니다.

### 2. 엔드포인트 Egress 권한 부여 및 Vertex AI Agent Engine에 `mortgage-agent` 배포

먼저 프로젝트 내 에이전트가 기본 Google API 엔드포인트(`aiplatform`, `agentregistry`, `iamcredentials`, `telemetry`)를 호출할 수 있도록 권한을 부여한 뒤, `uv`를 사용해 `mortgage-agent`를 배포합니다.

```bash
cd ~/agent-gateway-governance
chmod +x ./scripts/grant_agent_mcp_egress.sh

./scripts/grant_agent_mcp_egress.sh --bind-all-agents --endpoints

cd ~/agent-gateway-governance/src/mortgage-agent
uv sync

uv run python deploy_agent.py \
  --project="${PROJECT_ID}" \
  --region="${REGION}" \
  --enable-agent-identity \
  --agent-name=mortgage-agent \
  --agent-gateway="projects/${PROJECT_ID}/locations/${REGION}/agentGateways/agent-gateway" \
  --mcp-invoker-sa="$(terraform -chdir=../../terraform output -raw agent_mcp_invoker_email)" \
  --model-endpoint-location=global
```

> **참고**: Vertex AI Agent Engine에 Reasoning Engine이 배포되는 데 약 3~5분이 소요됩니다.

### 3. MCP 서버별 조건부 IAP CEL Egress 권한(`roles/iap.egressor`) 부여

배포된 에이전트의 Reasoning Engine ID(`AGENT_ID`)를 조회한 후, Agent Registry에 등록된 3개 MCP 서버에 대해 `roles/iap.egressor` 권한을 차등 부여합니다.

1. **`legacy-dms` 및 `income-verification`**: 모든 도구 호출 허용 (조건 없음)
2. **`corporate-email`**: **조건부 CEL 정책(`ReadOnlyToolsOnly`)**을 적용하여 읽기 전용 도구(`isReadOnly == true`: `search_emails`, `read_email`)와 MCP 초기화/목록 조회(`toolName == ''`)만 허용하고, 쓰기 도구인 `send_email`(`isReadOnly == false`)은 거부합니다.

```bash
cd ~/agent-gateway-governance

export AGENT_ID=$(gcloud beta ai reasoning-engines list \
  --project="${PROJECT_ID}" \
  --region="${REGION}" \
  --filter='displayName="Mortgage Assistant Agent"' \
  --format='value(name)' | head -n 1 | awk -F'/' '{print $NF}')
echo "AGENT_ID: ${AGENT_ID}"

# 1. legacy-dms 및 income-verification에 대해 무조건부 Egress 허용
./scripts/grant_agent_mcp_egress.sh \
  --mcp \
  --agent-id "${AGENT_ID}" \
  --mcp-filter "legacy-dms income-verification"

# 2. corporate-email에 대해 읽기 전용 도구만 허용하는 조건부 CEL(ReadOnlyToolsOnly) 바인딩
./scripts/grant_agent_mcp_egress.sh \
  --mcp \
  --agent-id "${AGENT_ID}" \
  --mcp-filter "corporate-email" \
  --condition-expression "api.getAttribute('iap.googleapis.com/mcp.tool.isReadOnly', false) == true || api.getAttribute('iap.googleapis.com/mcp.toolName', '') == ''" \
  --condition-title "ReadOnlyToolsOnly" \
  --condition-description "Restrict ${AGENT_ID} to read-only tools on corporate-email"
```

> **참고**: IAM 정책 변경 사항이 Google Cloud 전역에 전파되는 데 약 60초가 소요될 수 있습니다.

<ql-activity-tracking step=3>
Vertex AI Agent Engine 배포 및 조건부 IAP CEL 권한 설정 확인하기
</ql-activity-tracking>

---

## 작업 5. 1단계 검증: IAP `DRY_RUN` 모드 및 Model Armor PII 마스킹 테스트

이제 Google Cloud 콘솔의 Agent Engine Playground에서 에이펙스 금융그룹의 주택담보대출 심사 시나리오를 실행하여 두 가지를 동시에 검증합니다.

1. **Model Armor + Cloud DLP** (`CONTENT_AUTHZ`): `legacy-dms`와 `income-verification`이 반환한 김민준·이서연 부부의 주민등록번호(`850315-1234566`, `870822-2345673`)와 SSN(`323-45-6789`, `321-54-9876`)이 `[KOREA_RRN]` 및 `[US_SOCIAL_SECURITY_NUMBER]`로 마스킹되는지 확인합니다.
2. **IAP** (`REQUEST_AUTHZ` - `DRY_RUN` 모드): `corporate-email`의 `send_email` 도구가 `ReadOnlyToolsOnly` CEL 조건을 위반함에도 현재 `agent-gateway-iap-authz`가 `DRY_RUN` 상태이므로 차단되지 않고 실행되는지 확인합니다.

![DRY_RUN 모드와 ENFORCED 모드의 동작 차이 및 관측성 대시보드](img/03-dryrun-vs-enforced-flow.png)

### 1. Vertex AI Agent Engine Playground 열기

1. Google Cloud 콘솔 상단 검색창에 **Agent Engine**을 입력하고 **Vertex AI > Agent Engine**으로 이동합니다.
2. 리전이 `us-central1`로 선택되어 있는지 확인한 후, 배포된 **`Mortgage Assistant Agent`**를 클릭합니다.
3. 상단 탭에서 **Playground**를 클릭합니다.

### 2. 주택담보대출 심사 및 이메일 발송 프롬프트 실행

Playground 채팅창에 다음 프롬프트(한국어 또는 영문)를 입력하고 실행합니다.

```text
김민준(Minjun Kim)과 이서연(Seoyeon Lee) 부부가 2026년 신규 주택담보대출 적격 요건을 충족하는지 심사해 주세요.
1) legacy-dms에서 김민준 가족의 세금 신고서(소득금액증명원)와 문서 메타데이터를 조회해 주민등록번호(RRN)와 SSN, 소득을 확인하고,
2) income-verification으로 두 사람의 소득 및 2026년 DTI 비율을 검증한 뒤,
3) corporate-email에서 최신 2026년 언더라이팅 DTI 한도 지침 이메일을 찾아 읽고,
4) 심사 요약 결과를 underwriting-team@apex-financial.kr 로 이메일 발송(send_email)해 주세요.
```

### 3. 에이전트 응답 결과 확인

에이전트가 3개 MCP 서버의 도구를 차례대로 호출한 뒤 다음과 같은 결과를 반환하는지 확인합니다.

* **개인정보 마스킹 확인** (Model Armor + Cloud DLP 작동):
  * 원본 데이터에 저장된 김민준의 주민등록번호 `850315-1234566`과 이서연의 주민등록번호 `870822-2345673`이 `[KOREA_RRN]`으로 마스킹되어 표시됩니다.
  * 미국 SSN `323-45-6789`, `321-54-9876` 역시 `[US_SOCIAL_SECURITY_NUMBER]`로 마스킹되어 LLM 컨텍스트와 화면 어디에도 원본 번호가 노출되지 않습니다.
* **2026년 DTI 심사 및 이메일 발송 확인** (IAP `DRY_RUN` 모드):
  * 사내 이메일(`msg-002`)에 명시된 2026년 신규 주택담보대출 최대 DTI 한도(45.0%) 대비 김민준·이서연 부부의 추정 합산 DTI(28.4%, 합산 연소득 $237,000)가 기준 이하이므로 적격(Eligible) 판정이 내려집니다.
  * 현재 IAP 확장(`agent-gateway-iap-authz`)이 `DRY_RUN` 모드이므로 `send_email` 도구 호출이 차단되지 않고 성공(`status: sent`)합니다.

---

## 작업 6. 통합 관측성(Observability) 대시보드 및 Cloud Trace · Logging 분석

Agent Gateway는 통과하는 모든 MCP 트래픽에 대해 표준 메트릭, 분산 트레이스(Cloud Trace), 보안 감사 로그(Cloud Logging)를 자동으로 생성합니다.

### 1. Cloud Monitoring 거버넌스 대시보드 확인

1. Google Cloud 콘솔에서 **Monitoring > Dashboards(대시보드)**로 이동합니다.
2. Terraform이 생성한 **`Agent Gateway Governance`** 대시보드를 클릭합니다.

![Agent Gateway Governance Overview 대시보드](img/05-observability-dashboard.png)

대시보드에서 다음 핵심 지표를 확인할 수 있습니다.

* **MCP Request Rate by Tool**: `search_tax_returns`, `get_document_metadata`, `verify_income`, `search_emails`, `read_email`, `send_email` 등 도구별 호출 빈도
* **Agent Gateway Latency** (p50 / p95): 게이트웨이 및 Service Extensions(IAP, Model Armor) 처리 지연 시간
* **Model Armor & IAP Verdicts**: `REQUEST_AUTHZ` 및 `CONTENT_AUTHZ` 단계에서 PII 탐지·마스킹 또는 정책 평가가 수행된 요청 현황

### 2. Cloud Logging에서 Agent Gateway 및 Model Armor 로그 조회

Cloud Shell에서 다음 명령어를 실행하여 Agent Gateway를 통과한 MCP 요청 및 보안 확장 프로그램 로그를 조회합니다.

```bash
gcloud logging read \
  'resource.type="networkservices.googleapis.com/AgentGateway" OR protoPayload.serviceName="iap.googleapis.com" OR protoPayload.serviceName="modelarmor.googleapis.com"' \
  --project="${PROJECT_ID}" \
  --limit=10 \
  --format="table(timestamp, resource.type, httpRequest.status, jsonPayload.mcpMethod, jsonPayload.mcpToolName)"
```

---

## 작업 7. 2단계 검증: IAP `ENFORCED` 모드 전환 및 `send_email` 실시간 차단 확인

`DRY_RUN` 테스트와 관측성 대시보드를 통해 정상적인 조회 도구(`search_emails`, `read_email`)는 `ReadOnlyToolsOnly` CEL 조건을 통과하고 `send_email`만 정책 위반으로 탐지되는 것을 확인했습니다. 이제 IAP 확장(`agent-gateway-iap-authz`)을 **강제 적용 모드(`agent_gateway_iap_iam_enforcement_mode = null`)**로 전환하여 에이전트의 무단 외부 이메일 발송을 실시간 차단합니다.

### 1. Terraform으로 `agent_gateway_iap_iam_enforcement_mode = null` (Enforced 모드) 적용

Cloud Shell에서 `terraform/terraform.tfvars`의 `agent_gateway_iap_iam_enforcement_mode`를 `"DRY_RUN"`에서 `null`로 변경하고 `terraform apply`를 실행합니다.

```bash
cd ~/agent-gateway-governance

sed -i 's|agent_gateway_iap_iam_enforcement_mode = "DRY_RUN"|agent_gateway_iap_iam_enforcement_mode = null|g' terraform/terraform.tfvars

terraform -chdir=terraform apply -auto-approve
```

> **참고**: IAP 설정 변경 사항이 Agent Gateway 데이터 플레인에 반영되는 데 약 60초가 소요됩니다.

### 2. Playground에서 `send_email` 실시간 차단 확인

60초 후 **Vertex AI > Agent Engine > `Mortgage Assistant Agent` > Playground**로 돌아가서 새로운 세션을 열고 동일한 프롬프트를 다시 입력합니다.

```text
김민준(Minjun Kim)과 이서연(Seoyeon Lee) 부부의 2026년 주택담보대출 적격 여부를 다시 심사하고, 결과를 underwriting-team@apex-financial.kr 로 이메일 발송(send_email)해 주세요.
```

이번에는 다음과 같은 거버넌스 동작을 확인할 수 있습니다.

1. **조회 및 PII 마스킹 정상 수행**: `legacy-dms`(`search_tax_returns`), `income-verification`(`verify_income`), `corporate-email`(`search_emails`, `read_email`) 호출은 모두 정상 허용되며, 주민등록번호(`[KOREA_RRN]`)와 SSN(`[US_SOCIAL_SECURITY_NUMBER]`)은 계속 안전하게 마스킹됩니다.
2. **`send_email` 호출 즉시 차단**: 에이전트가 마지막 단계에서 `send_email` 도구를 호출하는 순간, Agent Gateway의 IAP(`REQUEST_AUTHZ`)가 `ReadOnlyToolsOnly` CEL 조건(`isReadOnly == false`)을 평가하여 요청을 `403 PermissionDenied`로 즉시 차단합니다.
3. **에이전트의 우아한 폴백**(Graceful Degradation): 에이전트는 심사 결과 보고서를 화면에는 정상 출력하되, 보안 정책(접근 제어 제한)으로 인해 `send_email` 도구 호출이 거부되어 이메일을 발송할 수 없다고 안내합니다.

<ql-activity-tracking step=4>
IAP Enforced 모드 전환 및 send_email 차단 검증 확인하기
</ql-activity-tracking>

---

## 축하합니다!

에이펙스 금융그룹의 주택담보대출 심사 시나리오를 통해 Agent Gateway, Identity-Aware Proxy(IAP CEL), Model Armor + Cloud DLP(KOREA_RRN/SSN 마스킹), 그리고 Cloud Monitoring/Trace 통합 관측성을 결합한 엔터프라이즈 에이전트 거버넌스 아키텍처를 성공적으로 구축하고 검증했습니다!

### 핵심 요약

* **클라이언트 사이드(`agent-egress`) & 서버 사이드(`cloud-run`) 통합 제어**: 외부/레거시 API와 내부 Cloud Run MCP 서버 모두 코드 변경 없이 Agent Gateway로 보호했습니다.
* **데이터 유출 방지** (`CONTENT_AUTHZ`): Model Armor와 Cloud DLP를 연동하여 MCP `structuredContent` 응답에 포함된 한국 주민등록번호(`[KOREA_RRN]`)와 미국 SSN(`[US_SOCIAL_SECURITY_NUMBER]`)을 LLM 컨텍스트 유입 전에 자동 마스킹했습니다.
* **컨텍스트 인식 도구 인가** (`REQUEST_AUTHZ`): IAP의 CEL 표현식과 `DRY_RUN` ➔ `ENFORCED` 배포 라이프사이클을 활용해 안전한 읽기 도구(`search_emails`, `read_email`)는 허용하고 고위험 쓰기 도구(`send_email`)는 정밀 차단했습니다.
