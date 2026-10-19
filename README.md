# 에이펙스 금융그룹(Apex Financial Group) Agent Gateway 워크로드 거버넌스

[Governing agentic workloads with Agent Gateway on Gemini Enterprise Agent Platform](https://codelabs.developers.google.com/cloudnet-agent-gateway) 공식 코드랩을 기반으로, **한국 금융권 주택담보대출 자동 심사 시나리오(공동 신청자 김민준·이서연 부부)** 및 **한국 주민등록번호(`KOREA_RRN`) + 미국 사회보장번호(`US_SOCIAL_SECURITY_NUMBER`) 실시간 마스킹**을 적용한 실습 저장소입니다.

## 아키텍처 개요

![에이펙스 금융그룹 Agent Gateway 거버넌스 아키텍처](codelab-web/img/00-overall-architecture.png)

Vertex AI Agent Engine에서 실행되는 ADK 주택담보대출 심사 에이전트(`mortgage-agent`)는 백엔드 Cloud Run에 배포된 3개의 MCP 서버(`legacy-dms`, `income-verification`, `corporate-email`)를 **Agent Gateway**를 통해서만 호출합니다.

| MCP 서버 | 비즈니스 역할 | 노출된 MCP 도구 | Agent Gateway 토폴로지 | 적용되는 거버넌스 정책 |
| :--- | :--- | :--- | :--- | :--- |
| **`legacy-dms`** | 레거시 문서 관리 시스템 (2023·2024 소득금액증명원 조회) | `search_tax_returns`, `get_document_metadata` | Client-Side (`agent-egress`) | **Model Armor + Cloud DLP (`CONTENT_AUTHZ`)**: 주민등록번호(`850315-1234566` ➔ `[KOREA_RRN]`) 및 SSN(`323-45-6789` ➔ `[US_SOCIAL_SECURITY_NUMBER]`) 마스킹 |
| **`income-verification`** | 외부 소득 및 재직 검증 API (2026년 DTI 산출) | `verify_income` | Client-Side (`agent-egress`) | **Model Armor + Cloud DLP (`CONTENT_AUTHZ`)**: 외부 API 요청·응답 내 주민등록번호(`[KOREA_RRN]`) 및 SSN(`[US_SOCIAL_SECURITY_NUMBER]`) 양방향 마스킹 |
| **`corporate-email`** | 사내 이메일 및 언더라이팅 지침 서버 (2026년 최대 DTI 45% 공지) | `search_emails`, `read_email`, `send_email` | Server-Side (`cloud-run`) | **IAP + CEL (`REQUEST_AUTHZ`)**: `search_emails`·`read_email`은 허용하되 `send_email`은 차단 (`DRY_RUN` 테스트 후 `ENFORCED` 전환) |

## 저장소 디렉터리 구조

```text
agent-gateway-governance/
├── codelab-ko.html                       # 한국어 인터랙티브 웹 코드랩 가이드 (단일 파일)
├── codelab-web/                          # Cloud Run 웹 가이드 배포 디렉터리 (Nginx + Docker)
├── qwiklabs-bundle/
│   └── apex-agent-gateway-governance/    # Qwiklabs Markdown Lab 번들 (qwiklabs.yaml, assessment.yaml, assessments/*.rb, instructions/ko.md & en.md)
├── skaffold.yaml                         # 3종 MCP 서버 컨테이너 일괄 빌드 설정
├── scripts/
│   └── grant_agent_mcp_egress.sh         # Agent Identity에 Agent Gateway & Cloud Run IAM 권한 부여 (조직/무조직 프로젝트 자동 호환)
├── src/
│   ├── legacy-dms/                       # [MCP 서버 1] 소득금액증명원 조회 (KOREA_RRN & SSN 포함)
│   ├── income-verification-api/          # [MCP 서버 2] 소득/재직 검증 및 2026년 DTI 비율 산출
│   ├── corporate-email/                  # [MCP 서버 3] 사내 지침 메일 열람 및 이메일 발송(send_email)
│   └── mortgage-agent/                   # [ADK 에이전트] 주택담보대출 심사 에이전트 및 deploy_agent.py
└── terraform/                            # Cloud Run, Agent Gateway, IAP CEL, Model Armor/DLP, 대시보드 Terraform 모듈
```

## 빠른 시작 (Quick Start)

```bash
export PROJECT_ID=$(gcloud config get-value project)
export PROJECT_NUMBER=$(gcloud projects describe "${PROJECT_ID}" --format="value(projectNumber)")
export ORG_ID=$(gcloud projects get-ancestors "${PROJECT_ID}" --format='value(id)' | tail -n 1)
if [ "${ORG_ID}" = "${PROJECT_ID}" ] || [ "${ORG_ID}" = "${PROJECT_NUMBER}" ]; then export ORG_ID=""; fi
export REGION="us-central1"
USER_EMAIL=$(gcloud config get-value account)

# 1. GCS 상태 버킷 생성 및 Terraform으로 Agent Gateway, IAP(DRY_RUN), Model Armor(KOREA_RRN/SSN) 프로비저닝
gcloud storage buckets create "gs://${PROJECT_ID}-tfstate" --location="${REGION}" --uniform-bucket-level-access 2>/dev/null || true
cat <<EOF > terraform/backend.conf
bucket = "${PROJECT_ID}-tfstate"
prefix = "terraform/state"
EOF

cp terraform/example.tfvars terraform/terraform.tfvars
sed -i "s|YOUR_PROJECT_ID|${PROJECT_ID}|g" terraform/terraform.tfvars
sed -i "s|YOUR_ORG_ID|${ORG_ID}|g" terraform/terraform.tfvars
sed -i "s|YOUR_ADMIN_EMAIL|${USER_EMAIL}|g" terraform/terraform.tfvars

terraform -chdir=terraform init -backend-config=backend.conf
terraform -chdir=terraform apply -auto-approve

# 2. Skaffold로 3종 MCP 서버(legacy-dms, income-verification, corporate-email) 빌드 및 Cloud Run 배포
export MCP_INGRESS="all"
envsubst '${PROJECT_ID} ${REGION} ${MCP_INGRESS}' < skaffold.yaml.tmpl > skaffold.yaml
for tmpl in cloudrun/*.yaml.tmpl; do
  envsubst '${PROJECT_ID} ${REGION} ${MCP_INGRESS}' < "${tmpl}" > "${tmpl%.tmpl}"
done
skaffold run

# 3. Vertex AI Agent Engine에 mortgage-agent 배포 및 조건부 IAP CEL Egress 권한 부여
./scripts/grant_agent_mcp_egress.sh --bind-all-agents --endpoints
(cd src/mortgage-agent && uv sync && uv run python deploy_agent.py \
  --project="${PROJECT_ID}" \
  --region="${REGION}" \
  --enable-agent-identity \
  --agent-name=mortgage-agent \
  --agent-gateway="projects/${PROJECT_ID}/locations/${REGION}/agentGateways/agent-gateway" \
  --mcp-invoker-sa="$(terraform -chdir=../../terraform output -raw agent_mcp_invoker_email)" \
  --model-endpoint-location=global)

export AGENT_ID=$(gcloud beta ai reasoning-engines list --project="${PROJECT_ID}" --region="${REGION}" --filter='displayName="Mortgage Assistant Agent"' --format='value(name)' | head -n 1 | awk -F'/' '{print $NF}')
./scripts/grant_agent_mcp_egress.sh --mcp --agent-id "${AGENT_ID}" --mcp-filter "legacy-dms income-verification"
./scripts/grant_agent_mcp_egress.sh --mcp --agent-id "${AGENT_ID}" --mcp-filter "corporate-email" \
  --condition-expression "api.getAttribute('iap.googleapis.com/mcp.tool.isReadOnly', false) == true || api.getAttribute('iap.googleapis.com/mcp.toolName', '') == ''" \
  --condition-title "ReadOnlyToolsOnly" \
  --condition-description "Restrict ${AGENT_ID} to read-only tools on corporate-email"
```
