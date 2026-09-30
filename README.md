# Agent Gateway와 시맨틱 거버넌스 정책(SGP)을 활용한 엔터프라이즈 AI 에이전트 거버넌스

본 저장소는 Google Cloud의 **[Governing Autonomous AI Agents with Agent Gateway and Semantic Governance Policies](https://codelabs.developers.google.com/enterprise-agent-governance-sgp)** 공식 Codelab을 기반으로 엔터프라이즈 환경에서 즉시 검증 및 배포할 수 있도록 구현된 종합 레퍼런스 아키텍처 및 자동화 코드셋입니다.

---

## 🏛️ 솔루션 개요

대규모 언어 모델(LLM)을 기반으로 한 자율 에이전트가 데이터베이스, 결제 게이트웨이, 핵심 금융 거래 시스템과 직접 상호작용하는 경우 보안 취약점, 금융 사고, 규제 위반 위험이 발생할 수 있습니다.

본 솔루션은 **Google Cloud Agent Gateway**와 **Semantic Governance Policies (SGP)**를 활용하여, 에이전트의 도구 호출(Tool Invocation)이 백엔드 시스템에 도달하기 전 네트워크 경계에서 실시간으로 가로채어 자연어 비즈니스 규정을 기반으로 정책을 사전 검증하고 차단하는 **제로 트러스트(Zero-Trust) 거버넌스 계층**을 구축합니다.

```
[사용자 프롬프트]
      │
      ▼
[Vertex AI Agent Runtime] (대화형 뱅킹 ADK 에이전트)
      │
      ▼ (모든 Egress 도구 호출을 가로챔)
[Google Cloud Agent Gateway] (agent-egress, AGENT_TO_ANYWHERE)
      │
      ├──▶ [Private Service Connect (policy.internal)]
      │         │
      │         ▼
      │    [시맨틱 거버넌스 정책 (SGP) 엔진]
      │    - LLM-as-judge 기반 자연어 비즈니스 제약 조건 실시간 평가
      │    - 평가 결과: ALLOW 또는 DENY (상세 사유 포함)
      │
      ▼ (ALLOW 판정 시에만 전달)
[Cloud Run: Banking MCP Server] (/mcp JSON-RPC 2.0 엔드포인트)
      - get_account (계좌 조회)
      - lookup_customer_by_phone (고객 조회)
      - transfer_to_phone (계좌 이체)
      - pay_bill (공과금 납부)
```

---

## 📂 프로젝트 구성

```
agentgateway/
├── banking-mcp-server/             # 엔터프라이즈 Banking MCP 서버
│   ├── server.py                   # Model Context Protocol JSON-RPC 2.0 & /tools 엔드포인트
│   ├── Dockerfile                  # Cloud Run 배포용 컨테이너 명세
│   ├── requirements.txt            # Python 패키지 의존성 (fastapi, uvicorn, pydantic, mcp)
│   └── test_server.py              # 도구 기능 및 프로토콜 규격 단위 테스트
│
├── conversational-banking/         # Vertex AI Agent Runtime용 대화형 에이전트
│   ├── app/
│   │   ├── agent.py                # AgentRegistry 기반 동적 MCP 도구 바인딩 에이전트
│   │   └── fast_api_app.py         # 로컬 및 런타임용 서비스 래퍼
│   ├── Dockerfile                  # Agent Gateway Root CA 신뢰 환경이 구성된 컨테이너
│   ├── pyproject.toml              # ADK 및 Agent Identity/MCP 통합 패키지 정의
│   └── agents-cli-manifest.yaml    # Agents CLI 프로젝트 매니페스트
│
├── env.sh                          # 프로젝트 공통 환경 변수 및 설정
├── 01-setup-env.sh                 # 필수 API 활성화 및 Gateway 서비스 계정 IAM 설정
├── 02-setup-networking.sh          # Proxy Subnet, Network Attachment, PSC, Private DNS 구성
├── 03-setup-agent-gateway.sh       # Agent Gateway 및 콘텐츠 인가 정책(Authz Policy) 등록
├── 04-deploy-mcp.sh                # Cloud Run에 Banking MCP 서버 배포 및 호출 권한 부여
├── 05-register-mcp.sh              # Agent Registry 도구 등록 및 시스템 API Allowlist 등록
├── 06-deploy-agent.sh              # Vertex AI Agent Runtime에 에이전트 배포
├── 07-create-sgp-policy.sh         # 자연어 제약 조건 시맨틱 거버넌스 정책 생성
├── 08-test.sh                      # Playground 검증 가이드 및 Cloud Logging 조회 스크립트
├── 99-cleanup.sh                   # 생성된 클라우드 리소스 일괄 정리 스크립트
└── deploy-all.sh                   # 전체 배포 파이프라인 일괄 실행 스크립트
```

---

## 💡 주요 아키텍처 구성 요소

### 1. Banking MCP Server (`banking-mcp-server/`)
- 오픈소스 **Model Context Protocol (MCP)** 표준을 준수하는 엔터프라이즈 뱅킹 서비스입니다.
- **도구 명세 제공 (`GET /tools`)**: 등록 자동화를 위해 Codelab 규격에 맞춘 4종 도구의 JSON 스키마를 직접 제공합니다.
- **MCP 표준 통신 (`POST /mcp`)**: JSON-RPC 2.0 기반으로 `initialize`, `tools/list`, `tools/call`, `ping` 메서드를 완전하게 처리합니다.
- **제공 기능**:
  - `get_account(customer_id)`: 계좌 상세 정보 및 실시간 잔액 조회
  - `lookup_customer_by_phone(phone)`: 등록 전화번호로 고객 식별
  - `transfer_to_phone(customer_id, target_phone, amount)`: 전화번호 기반 송금 및 잔액 차감/가산
  - `pay_bill(customer_id, biller_name, account_number, amount)`: 가맹점 및 공과금 납부

### 2. Conversational Banking Agent (`conversational-banking/`)
- **Google Agent Development Kit (ADK)**를 통해 빌드된 금융 상담 자율 에이전트입니다.
- **Agent Registry 연동**: 하드코딩된 API 엔드포인트 대신 Google Cloud Agent Registry의 카탈로그 메타데이터를 기반으로 런타임에 MCP 도구 세트를 동적으로 로드합니다.
- **Agent Gateway 연계**: Agent Gateway의 프록시 및 사설 CA 인증서 신뢰 체계가 빌드 단계부터 반영되어 게이트웨이를 통한 안전한 Egress 통신을 보장합니다.

### 3. Agent Gateway & 네트워킹
- **Agent Gateway (`agent-egress`)**: 에이전트 런타임과 외부/사내 시스템 사이의 관리형 Egress 보안 프록시로 동작합니다 (`AGENT_TO_ANYWHERE`).
- **Private Service Connect (PSC)**: Google이 관리하는 내부 SGP 정책 엔진(`us-central1`)과 VPC를 안전한 비공개 전용선으로 연결합니다.
- **Cloud DNS**: `policy.internal.` 프라이빗 존을 구성하여 게이트웨이가 PSC 내부 IP로 자연스럽게 라우팅하도록 지원합니다.

### 4. 시맨틱 거버넌스 정책 (Semantic Governance Policies)
- 애플리케이션 코드를 수정하지 않고 자연어로 비즈니스 규정을 정의합니다.
  - 적용 규칙: `"Block any transfer value exceeding USD 1000."` (1,000 USD를 초과하는 모든 이체 차단)
- Agent Gateway가 도구 페이로드를 검사하여 SGP 엔진에 전달하고, 독립적인 LLM-as-judge가 정책 준수 여부를 판정합니다.

---

## 🛠️ 사전 준비 사항

- 결제가 활성화된 Google Cloud 프로젝트
- Google Cloud SDK (`gcloud`) 설치 및 로그인 완료:
  ```bash
  gcloud auth login
  gcloud auth application-default login
  gcloud config set project <YOUR_PROJECT_ID>
  ```
- `agents-cli` 설치 완료:
  ```bash
  uv tool install google-agents-cli
  # 또는
  pip install google-agents-cli
  ```

---

## 🧪 로컬 사전 검증

클라우드에 배포하기 전, 로컬 환경에서 Banking MCP 서버의 도구 동작과 JSON-RPC 프로토콜을 즉시 검증할 수 있습니다:

```bash
cd banking-mcp-server
python3 test_server.py
```

출력 결과 예시:
```text
Testing TOOLS structure...
✓ Tool schemas verified
Testing get_account...
✓ get_account passed: Alice Smith, balance: 10000.0
Testing lookup_customer_by_phone...
✓ lookup_customer_by_phone passed: Bob Jones
Testing transfer_to_phone under limit...
✓ transfer_to_phone passed
Testing JSON-RPC handler...
✓ JSON-RPC protocol methods passed

ALL MCP SERVER TESTS PASSED SUCCESSFULLY!
```

---

## 🚀 배포 가이드

### 방법 1. 일괄 배포 실행 (권장)
전체 설정 및 배포를 한 번에 진행하려면 다음 스크립트를 실행합니다:
```bash
./deploy-all.sh
```

### 방법 2. 단계별 수동 배포
인프라 구성 과정을 단계별로 확인하며 배포하려면 아래 스크립트를 순서대로 실행합니다:

```bash
# 1. API 활성화 및 Gateway 서비스 계정 IAM 권한 구성
./01-setup-env.sh

# 2. VPC 서브넷, Network Attachment, PSC Endpoint, Cloud DNS 구성
./02-setup-networking.sh

# 3. Agent Gateway 리소스 및 Content Authz Policy 등록
./03-setup-agent-gateway.sh

# 4. Cloud Run에 Banking MCP 서버 배포 및 호출 권한 부여
./04-deploy-mcp.sh

# 5. Agent Registry에 MCP 도구 및 Google 시스템 API 등록
./05-register-mcp.sh

# 6. Vertex AI Agent Runtime에 Conversational Banking 에이전트 배포
./06-deploy-agent.sh

# 7. 시맨틱 거버넌스 정책(SGP) 생성 (1,000 USD 초과 이체 차단)
./07-create-sgp-policy.sh
```

---

## 🔍 Vertex AI Playground 검증 시나리오

1. Google Cloud Console에서 **Vertex AI** > **Reasoning Engines** (또는 Agent Engine)으로 이동합니다.
2. 배포된 **`conversational-banking`** 에이전트를 선택하고 **Playground** 탭을 클릭합니다.

### Turn 1: 고객 인증 및 잔액 조회
- **입력**: `I am customer CUST005`
- **동작**: 에이전트가 `get_account(customer_id="CUST005")` 도구를 호출하여 고객 Alice Smith를 인증하고 현재 잔액($10,000.00)과 서비스 메뉴를 안내합니다.

### Turn 2: 정책 허용 트랜잭션 테스트 (한도 미만)
- **입력**: `transfer 50 to 555-0001`
- **동작**:
  1. 에이전트가 `transfer_to_phone(customer_id="CUST005", target_phone="555-0001", amount=50)` 호출을 생성합니다.
  2. 요청이 Agent Gateway를 거쳐 PSC를 통해 SGP 엔진으로 전달됩니다.
  3. $50.00는 $1,000.00 한도 이하이므로 SGP 엔진이 **`ALLOW`** 판정을 내립니다.
  4. 요청이 백엔드 Cloud Run MCP 서버로 전달되어 이체가 성공적으로 처리되고 잔액이 $9,950.00로 업데이트됩니다.

### Turn 3: 정책 차단 트랜잭션 테스트 (한도 초과)
- **입력**: `transfer 2000 to 555-0002`
- (확인 질문 시 `y` 입력)
- **동작**:
  1. 에이전트가 `transfer_to_phone(customer_id="CUST005", target_phone="555-0002", amount=2000)` 호출을 생성합니다.
  2. Agent Gateway가 요청을 가로채어 SGP 엔진에서 자연어 규정(`"Block any transfer value exceeding USD 1000."`)을 평가합니다.
  3. $2,000.00는 한도를 초과하므로 SGP 엔진이 **`DENY`** 판정과 사유를 게이트웨이로 반환합니다.
  4. **요청은 백엔드 MCP 서버에 도달하지 못하고 게이트웨이 레벨에서 즉시 차단**됩니다.
  5. 에이전트는 거부 사유를 수신하고 사용자에게 정중하게 안내합니다:
     ```text
     "This action is disallowed because the transfer amount of $2000.00 exceeds the high-value transfer limit of $1000.00."
     ```

---

## 📜 Cloud Logging 감사 로그 확인

모든 거버넌스 정책 평가 결과는 판정 사유(Rationale)와 함께 Cloud Logging에 완벽한 감사 추적으로 기록됩니다.

터미널에서 아래 명령어를 실행하여 감사 로그를 확인할 수 있습니다:

```bash
gcloud logging read 'logName="projects/'"${PROJECT_ID}"'/logs/semantic-governance-policy"' --limit=5 --format=json
```

로그 페이로드 예시 (`DENY` 판정 기록):
```json
{
  "actionName": "transfer_to_phone",
  "toolName": "transfer_to_phone",
  "verdict": "DENY",
  "rationale": "This action is disallowed because the transfer amount of $2000.00 exceeds the high-value transfer limit of $1000.00."
}
```

---

## 🧹 리소스 정리

실습 완료 후 불필요한 비용 발생을 방지하기 위해 생성된 리소스를 안전하게 삭제합니다:

```bash
./99-cleanup.sh
```
