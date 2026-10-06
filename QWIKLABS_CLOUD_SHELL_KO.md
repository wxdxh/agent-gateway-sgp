# ☁️ [Qwiklabs · Cloud Shell 전용] Gemini Enterprise · Agent Gateway & SGP 핸즈온 인스트럭션

> **실습 환경:** Google Cloud Qwiklabs (Google Cloud Skills Boost) + **Google Cloud Shell**  
> **총 예상 소요 시간:** **약 45분** (병렬 파이프라인 적용)  
> **사용 모델 및 엔드포인트:** `gemini-3.8-flash` · **Global Endpoint (`https://aiplatform.googleapis.com`, `GOOGLE_CLOUD_LOCATION=global`)**  
> **비즈니스 시나리오:** **에이펙스 자산운용(Apex Asset Management)** — 1회 이체 한도 **100만 원(`amount <= 1000.0`)** 초과 송금 실시간 차단

---

## Task 0. Qwiklabs 시작 및 Cloud Shell 환경 준비 (⏱ 5분)

### 1. Qwiklabs 랩 시작 및 Google Cloud 콘솔 로그인
1. Qwiklabs 화면 좌측 상단의 **[Start Lab]** 버튼을 클릭합니다.
2. 좌측 패널에 발급된 임시 실습 계정 정보를 확인합니다:
   - **Username:** `student-xx-xxxxxxxxxxxx@qwiklabs.net`
   - **Password:** 임시 비밀번호
   - **GCP Project ID:** `qwiklabs-gcp-xx-xxxxxxxxxxxx`
3. **[Open Google Console]** 버튼을 우클릭하여 **시크릿 창(Incognito Window)**에서 열고, 발급받은 Username과 Password로 로그인합니다.

### 2. Google Cloud Shell 활성화
1. Google Cloud 콘솔 우측 상단 툴바에서 **Activate Cloud Shell (`>_` 아이콘)**을 클릭합니다.
2. 하단 터미널 창이 열리면 **[Continue]**를 클릭하여 Cloud Shell 프로비저닝을 완료합니다.
3. Cloud Shell 터미널에서 아래 명령어를 실행하여 로그인 계정과 프로젝트 ID가 올바르게 설정되었는지 확인합니다 (권한 승인 팝업이 뜨면 **[Authorize]** 클릭):

```bash
gcloud auth list
gcloud config list project
```

> **참고:** 만약 `project` 항목이 비어 있다면 Qwiklabs 좌측 패널의 `GCP Project ID`를 복사하여 아래 명령을 실행하세요:
> ```bash
> gcloud config set project [QWIKLABS_PROJECT_ID]
> ```

### 3. 실습 리포지토리 클론 및 Cloud Shell 필수 도구(`uv`, `agents-cli`) 설치
Cloud Shell 홈 디렉터리(`$HOME`)에 실습 코드를 클론하고, Gemini Enterprise Agent Runtime 패키징 도구인 `uv`와 `google-agents-cli`를 설치합니다.

```bash
cd ~
git clone https://github.com/wxdxh/agent-gateway-sgp.git
cd ~/agent-gateway-sgp
chmod +x *.sh

# Cloud Shell에 uv 및 google-agents-cli 설치
curl -LsSf https://astral.sh/uv/install.sh | sh
export PATH="$HOME/.local/bin:$PATH"
echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.bashrc

uv tool install google-agents-cli
agents-cli --version
```

### 4. 공통 환경 변수 로드 (`source env.sh`)
```bash
cd ~/agent-gateway-sgp
source env.sh
```

**예상 출력:**
```text
==================================================
 Project ID:     qwiklabs-gcp-xx-xxxxxxxxxxxx
 Project Number: 1080321871308
 Location:       us-central1
 VPC Network:    default
 VPC Subnet:     default
 Agent GW SA:    serviceAccount:service-1080321871308@gcp-sa-agentgateway.iam.gserviceaccount.com
==================================================
```

> **💡 Cloud Shell 세션 재연결 시 팁:**  
> 실습 도중 Cloud Shell 탭이 재연결되더라도 `$HOME/agent-gateway-sgp` 폴더와 `.env.runtime` 파일은 영구 보존됩니다. 재연결 시 아래 한 줄만 실행하면 즉시 이어서 진행할 수 있습니다:
> ```bash
> cd ~/agent-gateway-sgp && source env.sh && [[ -f .env.runtime ]] && source .env.runtime
> ```

---

## Task 1. 필수 Google Cloud API 활성화 및 IAM 구성 (⏱ 3분)

### ⚡ 옵션 A: 스크립트로 한 번에 실행 (권장)
```bash
cd ~/agent-gateway-sgp
./01-setup-env.sh
```

### 🛠️ 옵션 B: Cloud Shell에서 개별 명령어로 직접 실행
스크립트 대신 각 명령어를 직접 실행하려면 아래 블록을 Cloud Shell에 복사하여 붙여넣으세요:

```bash
cd ~/agent-gateway-sgp
source env.sh

# 1. 필수 API 16종 일괄 활성화
gcloud services enable \
  compute.googleapis.com \
  networksecurity.googleapis.com \
  networkservices.googleapis.com \
  dns.googleapis.com \
  iam.googleapis.com \
  iap.googleapis.com \
  agentregistry.googleapis.com \
  aiplatform.googleapis.com \
  run.googleapis.com \
  cloudbuild.googleapis.com \
  artifactregistry.googleapis.com \
  storage.googleapis.com \
  modelarmor.googleapis.com \
  telemetry.googleapis.com \
  cloudtrace.googleapis.com \
  logging.googleapis.com \
  --project="${PROJECT_ID}"

# 2. Network Services 관리형 서비스 에이전트 ID 발급
gcloud beta services identity create \
  --service=networkservices.googleapis.com \
  --project="${PROJECT_ID}" || true

# 3. Agent Gateway 서비스 에이전트에 필수 IAM 역할 3종 부여
for ROLE in "roles/agentgateway.serviceAgent" "roles/aiplatform.user" "roles/modelarmor.user"; do
  gcloud projects add-iam-policy-binding "${PROJECT_ID}" \
    --member="${AGW_SA}" \
    --role="${ROLE}" \
    --condition=None \
    --quiet
done
```

### ✅ Task 1 완료 확인 (Cloud Shell 검증)
```bash
gcloud projects get-iam-policy "${PROJECT_ID}" \
  --flatten="bindings[].members" \
  --filter="bindings.members:${AGW_SA}" \
  --format="table(bindings.role)"
```

---

## Task 2. Agent Gateway 기반 구축 (`proxy-only-subnet` · `agent-gateway-na` · `agent-egress`) (⏱ 3분)

### ⚡ 옵션 A: 스크립트로 한 번에 실행 (권장)
```bash
cd ~/agent-gateway-sgp
./02-setup-agent-gateway.sh
```

### 🛠️ 옵션 B: Cloud Shell에서 개별 명령어로 직접 실행
```bash
cd ~/agent-gateway-sgp
source env.sh

# 1. 리전 관리형 프록시 전용 서브넷 생성
gcloud compute networks subnets create proxy-only-subnet \
  --network="${NETWORK_NAME}" \
  --region="${LOCATION}" \
  --range="10.11.13.0/24" \
  --purpose=REGIONAL_MANAGED_PROXY \
  --role=ACTIVE \
  --project="${PROJECT_ID}" || true

# 2. Agent Gateway Egress용 Network Attachment 생성
gcloud compute network-attachments create agent-gateway-na \
  --region="${LOCATION}" \
  --subnets="${SUBNET_NAME}" \
  --connection-preference=ACCEPT_AUTOMATIC \
  --project="${PROJECT_ID}" || true

# 3. AGENT_TO_ANYWHERE 모드의 Agent Gateway (agent-egress) 선언 및 임포트
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

gcloud network-services agent-gateways import agent-egress \
  --source=agent-gateway-vpc-egress.yaml \
  --location="${LOCATION}" \
  --project="${PROJECT_ID}"
```

### ✅ Task 2 완료 확인 (Cloud Shell 검증)
```bash
gcloud network-services agent-gateways describe agent-egress \
  --location="${LOCATION}" \
  --project="${PROJECT_ID}" \
  --format="yaml(name,googleManaged,networkConfig)"
```

---

## Task 3. 에이펙스 자산운용 뱅킹 MCP 서버 배포 (Cloud Run) (⏱ 3분)

### ⚡ 옵션 A: 스크립트로 한 번에 실행 (권장)
```bash
cd ~/agent-gateway-sgp
./03-deploy-mcp.sh
```

### 🛠️ 옵션 B: Cloud Shell에서 개별 명령어로 직접 실행
```bash
cd ~/agent-gateway-sgp
source env.sh

# 1. Cloud Run에 뱅킹 MCP 서버 컨테이너 빌드 및 배포
gcloud run deploy banking-mcp-server \
  --source=mcp_server \
  --region="${LOCATION}" \
  --project="${PROJECT_ID}" \
  --allow-unauthenticated \
  --quiet

# 2. 배포된 Cloud Run URL 추출 및 .env.runtime에 저장
export MCP_URL="$(gcloud run services describe banking-mcp-server \
  --region="${LOCATION}" \
  --project="${PROJECT_ID}" \
  --format="value(status.url)")"
echo "export MCP_URL=\"${MCP_URL}\"" > .env.runtime
echo "MCP_URL=${MCP_URL}"
```

### ✅ Task 3 완료 확인 (Cloud Shell 검증)
```bash
source .env.runtime
ID_TOKEN="$(gcloud auth print-identity-token)"
curl -fsS -H "Authorization: Bearer ${ID_TOKEN}" "${MCP_URL}/tools" | python3 -m json.tool | head -n 25
```

---

## Task 4. Agent Registry에 MCP 서버 및 Global API 엔드포인트 등록 (⏱ 3분)

> **핵심 포인트:** 에이전트가 **`gemini-3.8-flash`** 모델을 **Global Endpoint (`https://aiplatform.googleapis.com`)**로 호출하므로, `agent-egress` 게이트웨이의 Allowlist에 `Gemini Enterprise Global API | https://aiplatform.googleapis.com`을 포함한 4개 시스템 엔드포인트를 등록하고 `roles/iap.egressor` 권한을 부여합니다.

### ⚡ 옵션 A: 스크립트로 한 번에 실행 (권장)
```bash
cd ~/agent-gateway-sgp
./04-register-mcp.sh
```

### 🛠️ 옵션 B: Cloud Shell에서 개별 명령어로 직접 실행
```bash
cd ~/agent-gateway-sgp
source env.sh
source .env.runtime

# 1. MCP 서버에서 도구 스키마를 추출하여 toolspec.json 생성
ID_TOKEN="$(gcloud auth print-identity-token 2>/dev/null || true)"
curl -fsS -H "Authorization: Bearer ${ID_TOKEN}" "${MCP_URL}/tools" | \
  python3 -c 'import sys, json; tools=json.load(sys.stdin); json.dump({"tools": tools}, open("toolspec.json", "w"))'

# 2. Agent Registry에 Banking MCP Server 등록
gcloud alpha agent-registry services create banking-mcp-server \
  --project="${PROJECT_ID}" \
  --location="${LOCATION}" \
  --display-name="Banking MCP Server" \
  --interfaces=url="${MCP_URL}/mcp",protocolBinding=JSONRPC \
  --mcp-server-spec-type=tool-spec \
  --mcp-server-spec-content="toolspec.json" || true

# 3. 할당된 MCP_SERVER_NAME 조회 및 저장
export MCP_SERVER_NAME="$(gcloud alpha agent-registry mcp-servers list \
  --project="${PROJECT_ID}" \
  --location="${LOCATION}" \
  --filter="displayName:'Banking MCP Server'" \
  --format="value(name.basename())" | head -n 1)"
echo "export MCP_SERVER_NAME=\"${MCP_SERVER_NAME}\"" >> .env.runtime
echo "MCP_SERVER_NAME=${MCP_SERVER_NAME}"

# 4. Gemini Enterprise Global API (https://aiplatform.googleapis.com) 외 필수 시스템 엔드포인트 4종 등록
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

  res="$(gcloud alpha agent-registry services create "${service_id}" \
    --project="${PROJECT_ID}" \
    --location="${LOCATION}" \
    --display-name="${name}" \
    --endpoint-spec-type=no-spec \
    --interfaces=url="${url}",protocolBinding=JSONRPC \
    --format="value(registryResource)" 2>&1)" || true

  ep_id="$(echo "${res}" | grep -oE 'agentregistry-[0-9a-f-]+$' | head -n 1 || true)"
  if [[ -n "${ep_id}" ]]; then
    gcloud alpha iap web add-iam-policy-binding \
      --resource-type=agent-registry --endpoint="${ep_id}" --region="${LOCATION}" \
      --project="${PROJECT_ID}" --member="${AGW_SA}" --role="roles/iap.egressor" --quiet >/dev/null || true
    gcloud alpha iap web add-iam-policy-binding \
      --resource-type=agent-registry --endpoint="${ep_id}" --region="${LOCATION}" \
      --project="${PROJECT_ID}" \
      --member="serviceAccount:service-${PROJECT_NUM}@gcp-sa-aiplatform-re.iam.gserviceaccount.com" \
      --role="roles/iap.egressor" --quiet >/dev/null || true
  fi
done
```

### ✅ Task 4 완료 확인 (Cloud Shell 검증)
```bash
gcloud alpha agent-registry services list \
  --project="${PROJECT_ID}" \
  --location="${LOCATION}" \
  --format="table(name.basename(),displayName)"
```

---

## Task 5. 🚀 Gemini Enterprise 에이전트 런타임 조기 비동기 배포 시작 (⏱ 2분 · 백그라운드 15~20분)

> **⚡ 병렬 파이프라인 안내:**  
> Gemini Enterprise Agent Runtime 프로비저닝은 백엔드에서 약 15~20분이 소요됩니다. `--no-wait` 옵션으로 **비동기 배포를 먼저 트리거(약 1~2분 소요)**한 뒤, **기다리지 말고 즉시 Task 6과 Task 7을 진행**하세요!

### ⚡ 옵션 A: 스크립트로 한 번에 실행 (권장)
```bash
cd ~/agent-gateway-sgp
./05-deploy-agent.sh
```

### 🛠️ 옵션 B: Cloud Shell에서 개별 명령어로 직접 실행
```bash
cd ~/agent-gateway-sgp
source env.sh
source .env.runtime
export PATH="$HOME/.local/bin:$PATH"

# 1. Agent Gateway의 TLS Inspection Root CA 인증서 추출
gcloud network-services agent-gateways describe agent-egress \
  --location="${LOCATION}" \
  --project="${PROJECT_ID}" \
  --format="value(agentGatewayCard.rootCertificates[0])" > conversational-banking/agent-gateway-ca.crt

# 2. Gemini 3.8 Flash + Global Endpoint (GOOGLE_CLOUD_LOCATION=global) 환경 변수로 비동기 배포 시작
cd ~/agent-gateway-sgp/conversational-banking
export UV_NO_CONFIG=1
export PIP_CONFIG_FILE=/dev/null

agents-cli deploy \
  --project="${PROJECT_ID}" \
  --region="${LOCATION}" \
  --deployment-target="agent_runtime" \
  --agent-identity \
  --agent-gateway-egress="projects/${PROJECT_ID}/locations/${LOCATION}/agentGateways/agent-egress" \
  --update-env-vars="MCP_SERVER_NAME=${MCP_SERVER_NAME},GOOGLE_CLOUD_LOCATION=global,LOCATION=${LOCATION},MODEL=gemini-3.8-flash,PROJECT_ID=${PROJECT_ID},GOOGLE_API_USE_MTLS_ENDPOINT=never,GOOGLE_API_USE_CLIENT_CERTIFICATE=false" \
  --no-wait

cd ~/agent-gateway-sgp
```

---

## Task 6. (병렬 진행 1) SGP 정책 엔진 활성화 · PSC 엔드포인트 및 프라이빗 DNS 구성 (⏱ 5분)

백그라운드에서 에이전트 런타임이 프로비저닝되는 동안, SGP(시맨틱 거버넌스 정책) 엔진과 Private Service Connect(PSC) 전용 터널 및 프라이빗 DNS(`policy.internal.`)를 구성합니다.

### ⚡ 옵션 A: 스크립트로 한 번에 실행 (권장)
```bash
cd ~/agent-gateway-sgp
./06-setup-sgp-networking.sh
```

### 🛠️ 옵션 B: Cloud Shell에서 개별 명령어로 직접 실행
```bash
cd ~/agent-gateway-sgp
source env.sh

# 1. SGP 정책 엔진 활성화 및 전용 Service Attachment URI 조회
TOKEN="$(gcloud auth print-access-token)"
curl -fsS -X PATCH \
  -H "Authorization: Bearer ${TOKEN}" \
  -H "Content-Type: application/json" \
  -H "X-Goog-User-Project: ${PROJECT_ID}" \
  "https://networksecurity.googleapis.com/v1alpha1/projects/${PROJECT_ID}/locations/${LOCATION}/semanticGovernancePolicyEngine?updateMask=state" \
  -d '{"state": "ENABLED"}'

export SERVICE_ATTACHMENT="$(curl -fsS \
  -H "Authorization: Bearer ${TOKEN}" \
  -H "X-Goog-User-Project: ${PROJECT_ID}" \
  "https://networksecurity.googleapis.com/v1alpha1/projects/${PROJECT_ID}/locations/${LOCATION}/semanticGovernancePolicyEngine" | \
  python3 -c 'import sys, json; print(json.load(sys.stdin).get("serviceAttachment", ""))')"
echo "SERVICE_ATTACHMENT=${SERVICE_ATTACHMENT}"

# 2. VPC 내부 고정 IP 예약 및 PSC Forwarding Rule 생성
gcloud compute addresses create sgp-psc-ip \
  --region="${LOCATION}" \
  --subnet="${SUBNET_NAME}" \
  --project="${PROJECT_ID}" || true

export PSC_IP="$(gcloud compute addresses describe sgp-psc-ip \
  --region="${LOCATION}" \
  --project="${PROJECT_ID}" \
  --format="value(address)")"
echo "PSC_IP=${PSC_IP}"

gcloud compute forwarding-rules create sgp-psc-endpoint \
  --region="${LOCATION}" \
  --network="${NETWORK_NAME}" \
  --address=sgp-psc-ip \
  --target-service-attachment="${SERVICE_ATTACHMENT}" \
  --project="${PROJECT_ID}" || true

# 3. Cloud DNS 프라이빗 존(policy.internal.) 및 와일드카드 A 레코드 등록
gcloud dns managed-zones create sgp-private-zone \
  --dns-name="policy.internal." \
  --description="Private zone for SGP endpoint" \
  --visibility=private \
  --networks="${NETWORK_NAME}" \
  --project="${PROJECT_ID}" || true

gcloud dns record-sets create "*.${LOCATION}.policy.internal." \
  --zone=sgp-private-zone \
  --type=A \
  --ttl=300 \
  --rrdatas="${PSC_IP}" \
  --project="${PROJECT_ID}" || true
```

### ✅ Task 6 완료 확인 (Cloud Shell 검증)
```bash
gcloud compute forwarding-rules describe sgp-psc-endpoint \
  --region="${LOCATION}" \
  --project="${PROJECT_ID}" \
  --format="table(name,IPAddress,pscConnectionStatus)"
```

---

## Task 7. (병렬 진행 2) 인가 확장 · AuthzPolicy 및 100만 원 한도 SGP 정책 생성 (⏱ 5분)

`07-create-sgp-policy.sh`는 인가 확장(`sgp-authzextension`)과 `AuthzPolicy`를 먼저 생성한 뒤, Task 5에서 비동기로 시작한 에이전트 런타임의 **Agent Identity(`AGENT_ID`)** 발급 완료 여부를 자동으로 폴링하여 확인하고 **100만 원(`amount <= 1000.0`) 이체 한도 정책(`high-value-limit`)**을 배포합니다.

### ⚡ 옵션 A: 스크립트로 한 번에 실행 (권장)
```bash
cd ~/agent-gateway-sgp
./07-create-sgp-policy.sh
```

### 🛠️ 옵션 B: Cloud Shell에서 개별 명령어로 직접 실행
```bash
cd ~/agent-gateway-sgp
source env.sh
source .env.runtime

# 1. SGP 엔드포인트 호출용 AuthzExtension 생성
gcloud service-extensions authz-extensions import sgp-authzextension \
  --location="${LOCATION}" \
  --project="${PROJECT_ID}" << EOF
name: projects/${PROJECT_ID}/locations/${LOCATION}/authzExtensions/sgp-authzextension
authority: ext1.${LOCATION}.policy.internal
service: https://sgp.${LOCATION}.policy.internal
timeout: 1s
failOpen: false
forwardHeaders:
  - Authorization
wireFormat: EXT_PROC_GRPC
EOF

# 2. Agent Gateway와 AuthzExtension을 연결하는 AuthzPolicy 생성
cat > agent-egress-sgp-authzpolicy.yaml << EOF
name: projects/${PROJECT_ID}/locations/${LOCATION}/authzPolicies/agent-egress-sgp-authzpolicy
target:
  resources:
    - projects/${PROJECT_ID}/locations/${LOCATION}/agentGateways/agent-egress
  loadBalancingScheme: INTERNAL_MANAGED
action: CUSTOM
customProvider:
  authzExtension:
    resources:
      - projects/${PROJECT_ID}/locations/${LOCATION}/authzExtensions/sgp-authzextension
httpRules:
  - to:
      operations:
        - hosts:
            - "${MCP_URL#https://}"
          paths:
            - exact: "/mcp"
          methods: ["POST"]
          mcp: {}
EOF

gcloud network-security authz-policies import agent-egress-sgp-authzpolicy \
  --source=agent-egress-sgp-authzpolicy.yaml \
  --location="${LOCATION}" \
  --project="${PROJECT_ID}"

# 3. 에이전트 런타임 배포 완료 대기 및 AGENT_ID 추출 후 SGP 정책 배포
./07-create-sgp-policy.sh
```

### ✅ Task 7 완료 확인 (Cloud Shell 검증)
```bash
gcloud beta network-security semantic-governance-policies describe high-value-limit \
  --location="${LOCATION}" \
  --project="${PROJECT_ID}"
```

---

## Task 8. 3-Turn 시맨틱 거버넌스 정책 검증 및 감사 로그 확인 (⏱ 5분)

모든 구성이 완료되었습니다! 이제 Cloud Shell에서 3-Turn 시나리오 테스트를 실행하여 **5만 원 송금은 허용(`ALLOW`)**되고 **500만 원 고액 송금은 실시간 차단(`DENY`)**되는지 검증합니다.

### 1. 3-Turn 자동화 검증 스크립트 실행 (`08-test.sh`)
```bash
cd ~/agent-gateway-sgp
./08-test.sh
```

**Cloud Shell 예상 출력:**
```text
================================================================================
 Starting 3-Turn Governance Verification against Agent Engine: 8000083135147507712
================================================================================

--- [Turn 1] Account Inquiry (get_account) ---
User: 안녕하세요, 저는 에이펙스 자산운용 고객번호 CUST005입니다. 제 계좌 잔액을 확인해 주세요.
  [Tool Call]   get_account(args={'customer_id': 'CUST005'})
  [Tool Result] get_account -> {'balance': 10000.0, 'customer_id': 'CUST005', 'name': 'Eva Green'}
Agent: 안녕하세요, Eva Green 고객님(고객번호: CUST005)! 현재 계좌 잔액은 1,000만 원($10,000.00)입니다.

--- [Turn 2] Low-Value Transfer: 50,000 KRW (Expected: ALLOW) ---
User: 전화번호 555-0001번으로 5만 원(amount: 50)을 송금해 주세요. 바로 실행해 주세요.
  [Tool Call]   transfer_to_phone(args={'amount': 50, 'customer_id': 'CUST005', 'target_phone': '555-0001'})
  [Tool Result] transfer_to_phone -> {'amount': 50.0, 'sender_new_balance': 9950.0, 'status': 'success'}
Agent: 555-0001번(Alice)으로 5만 원($50.00) 송금이 정상적으로 완료되었습니다.

--- [Turn 3] High-Value Transfer: 5,000,000 KRW (Expected: DENY by SGP) ---
User: 같은 번호(555-0001)로 500만 원(amount: 5000)을 추가로 송금해 주세요. 바로 실행해 주세요.
  [Tool Call]   transfer_to_phone(args={'amount': 5000, 'customer_id': 'CUST005', 'target_phone': '555-0001'})
  [Tool Result] transfer_to_phone -> {'error': 'Tool call transfer_to_phone rejected by semantic governance policy.'}
Agent: 죄송합니다, 고객님. 요청하신 500만 원($5,000.00) 추가 송금은 보안 및 시맨틱 거버넌스 정책(1회 이체 한도 100만 원 초과)에 의해 거부되어 실행할 수 없습니다.
```

### 2. Cloud Logging 감사 로그 확인 (Cloud Shell)
```bash
gcloud logging read \
  'jsonPayload.enforcedSecurityPolicy.matchedRules.name:"high-value-limit" OR textPayload:"transfer_to_phone"' \
  --project="${PROJECT_ID}" \
  --limit=10 \
  --format="yaml(timestamp,httpRequest.status,jsonPayload)"
```
