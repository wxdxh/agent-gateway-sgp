# Gemini Enterprise와 Agent Gateway · 시맨틱 거버넌스 정책(SGP)을 활용한 엔터프라이즈 AI 에이전트 거버넌스

본 저장소는 Google Cloud의 **Gemini Enterprise**, **Agent Gateway**, **Semantic Governance Policies (SGP)**를 결합하여 자율형 AI 에이전트의 도구 호출(Tool Invocation)을 네트워크 경계에서 실시간으로 통제하고 감사하는 종합 레퍼런스 아키텍처 및 실습 코드셋입니다.

> 📘 **상세 단계별 퀵랩(Quicklab) 실습 지침서 바로가기**: **[`CODELAB_INSTRUCTIONS_KO.md`](./CODELAB_INSTRUCTIONS_KO.md)**

---

## 🏦 비즈니스 시나리오: 에이펙스 자산운용 (Apex Asset Management)

국내 금융사인 **에이펙스 자산운용**은 고객이 대화만으로 계좌 조회, 간편 송금, 공과금 납부를 수행할 수 있도록 **Gemini Enterprise** 기반의 대화형 뱅킹 에이전트를 도입했습니다. 금융보안 및 준법감시팀은 보이스피싱 및 고액 오송금 사고를 예방하기 위해, 에이전트 코드를 수정하지 않고도 다음의 비즈니스 규정을 네트워크 경계에서 강제합니다:

> **핵심 거버넌스 규정**: *"1회 이체 금액이 100만 원(1,000,000 KRW / 1,000 USD)을 초과하는 모든 송금 요청은 네트워크 경계에서 즉시 차단하고 감사 로그를 남긴다."*

```mermaid
flowchart LR
    User(["👤 금융 고객<br/>김민준 (CUST005)"])
    Agent["🤖 Gemini Enterprise<br/>대화형 뱅킹 에이전트<br/>(ADK · Agent Identity)"]
    Gateway["🛡️ Google Cloud<br/>Agent Gateway<br/>(agent-egress)"]
    Registry["📒 Agent Registry<br/>도구 카탈로그 & Allowlist"]
    SGP["⚖️ SGP 정책 엔진 (PSC)<br/>100만 원 초과 이체 심사<br/>(ALLOW / DENY)"]
    MCP["🏦 Cloud Run<br/>뱅킹 MCP 서버<br/>(계좌조회 · 송금 · 납부)"]
    Logs["📜 Cloud Logging<br/>SGP 감사 로그"]

    User -->|"3-Turn 대화"| Agent
    Agent -->|"① 호출 가로채기"| Gateway
    Registry -.->|"도구 스키마 & 허가"| Agent
    Registry -.->|"라우팅 정책"| Gateway
    Gateway -->|"② 정책 심사 요청 (PSC)"| SGP
    SGP -->|"③ ALLOW / DENY 판정"| Gateway
    Gateway -->|"④ ALLOW 시에만 전달"| MCP
    SGP -.->|"판정 근거 기록"| Logs
```

---

## ⏱️ 한눈에 보는 실습 로드맵 (총 예상 시간: 약 55분)

| 단계 | 실행 스크립트 | 핵심 작업 | 예상 시간 | 실무 체크포인트 |
| :---: | :--- | :--- | :---: | :--- |
| **Step 1** | [`CODELAB_INSTRUCTIONS_KO.md`](./CODELAB_INSTRUCTIONS_KO.md) | 에이펙스 자산운용 시나리오 및 아키텍처 이해 | **5분** | 네트워크 경계 기반 정책 통제 구조 파악 |
| **Step 2** | `01-setup-env.sh` | 필수 API 활성화 및 Gateway 서비스 계정 권한 부여 | **5분** | `roles/agentgateway.serviceAgent` 필수 |
| **Step 3** | `02-setup-networking.sh` | Proxy Subnet, Network Attachment, PSC, DNS 구성 | **7분** | PSC 연결 상태 `ACCEPTED` 확인 |
| **Step 4** | `03-setup-agent-gateway.sh` | `agent-egress` 게이트웨이 및 인가 정책 배포 | **5분** | `policy.internal.` DNS 피어링 연결 |
| **Step 5** | `04-deploy-mcp.sh` | Cloud Run에 뱅킹 MCP 서버 배포 | **5분** | 4대 뱅킹 도구 스키마 응답 확인 |
| **Step 6** | `05-register-mcp.sh` | Agent Registry에 MCP 도구 및 시스템 API 등록 | **5분** | 시스템 엔드포인트 4종 Allowlist 등록 |
| **Step 7** | `06-deploy-agent.sh` | **Gemini Enterprise 에이전트 런타임 배포** | **15~20분** | **프로비저닝 중 절대 중단 금지** |
| **Step 8** | `07-create-sgp-policy.sh` | 고액 이체 차단 시맨틱 거버넌스 정책(SGP) 생성 | **3분** | 런타임 도구 접두사 매칭 확인 |
| **Step 9** | `08-test.sh` / `run_tests.py` | 3-Turn 시나리오 검증 및 Cloud Logging 감사 확인 | **5분** | 소액 이체 `ALLOW` / 고액 이체 `DENY` |

---

## 📂 프로젝트 디렉터리 구조

```text
agentgateway/
├── CODELAB_INSTRUCTIONS_KO.md      # 📘 단계별 한국어 Quicklab 실습 지침서 (Markdown)
├── codelab-ko.html                 # 🌐 대화형 한국어 Codelab 웹 가이드 (SVG 다이어그램 포함)
├── index.html                      # GitHub Pages용 대화형 Codelab 메인 페이지
│
├── banking-mcp-server/             # 에이펙스 자산운용 뱅킹 MCP 서버
│   ├── server.py                   # Model Context Protocol JSON-RPC 2.0 & /tools 엔드포인트
│   ├── Dockerfile                  # Cloud Run 배포용 컨테이너 명세
│   ├── requirements.txt            # Python 패키지 의존성
│   └── test_server.py              # 도구 기능 및 프로토콜 규격 단위 테스트
│
├── conversational-banking/         # Gemini Enterprise 에이전트 런타임용 대화형 에이전트
│   ├── app/
│   │   ├── agent.py                # Agent Registry 기반 동적 MCP 도구 바인딩 에이전트
│   │   └── fast_api_app.py         # 로컬 및 런타임용 서비스 래퍼
│   ├── Dockerfile                  # Agent Gateway TLS 신뢰 환경이 구성된 컨테이너
│   ├── pyproject.toml              # ADK 및 Agent Identity/MCP 통합 패키지 정의
│   └── agents-cli-manifest.yaml    # Agents CLI 프로젝트 매니페스트
│
├── env.sh                          # 프로젝트 공통 환경 변수 및 자동 감지 설정
├── 01-setup-env.sh                 # 필수 API 활성화 및 Gateway 서비스 계정 IAM 설정
├── 02-setup-networking.sh          # Proxy Subnet, Network Attachment, PSC, Private DNS 구성
├── 03-setup-agent-gateway.sh       # Agent Gateway 및 콘텐츠 인가 정책(Authz Policy) 등록
├── 04-deploy-mcp.sh                # Cloud Run에 뱅킹 MCP 서버 배포
├── 05-register-mcp.sh              # Agent Registry 도구 등록 및 시스템 API Allowlist 등록
├── 06-deploy-agent.sh              # Gemini Enterprise 에이전트 런타임 배포 (15~20분 소요)
├── 07-create-sgp-policy.sh         # 자연어 제약 조건 시맨틱 거버넌스 정책(SGP) 생성
├── 08-test.sh                      # 대화형 및 자동화 종합 검증 실행 스크립트
├── run_tests.py                    # E2E 3-Turn 자동화 검증 및 SGP 감사 로그 확인 스크립트
├── 99-cleanup.sh                   # 생성된 클라우드 리소스 일괄 정리 스크립트
└── deploy-all.sh                   # 전체 배포 파이프라인 일괄 실행 스크립트
```

---

## 🚀 빠른 실행 가이드

### 1. 일괄 배포 실행
```bash
./deploy-all.sh
```

### 2. 단계별 수동 배포 및 검증
상세한 단계별 설명과 아키텍처 가이드는 **[`CODELAB_INSTRUCTIONS_KO.md`](./CODELAB_INSTRUCTIONS_KO.md)** 문서를 참고하세요.

```bash
./01-setup-env.sh
./02-setup-networking.sh
./03-setup-agent-gateway.sh
./04-deploy-mcp.sh
./05-register-mcp.sh
./06-deploy-agent.sh        # 약 15~20분 소요 (중단 금지)
./07-create-sgp-policy.sh
./08-test.sh                # 3-Turn 자동화 검증 및 Cloud Logging 감사 로그 확인
```

---

## 🔍 3-Turn 시나리오 검증 요약

| 대화 순서 | 고객 입력 프롬프트 | SGP 판정 | 에이전트 최종 응답 |
| :---: | :--- | :---: | :--- |
| **Turn 1**<br/>(본인 확인) | `저는 고객번호 CUST005입니다`<br/>*(또는 `I am customer CUST005`)* | **`ALLOW`** | 안녕하세요! 계좌(`ACT-1005`)의 현재 잔액은 **10,000,000원(10,000 USD)**입니다. 무엇을 도와드릴까요? |
| **Turn 2**<br/>(소액 송금) | `555-0001로 5만 원(50) 이체해 줘`<br/>*(또는 `transfer 50 to 555-0001`)* | **`ALLOW`** | 수취인(`555-0001`)에게 정상 이체되었습니다. 거래번호: `TXN-C0832A85`, 남은 잔액: **9,950,000원(9,950 USD)** |
| **Turn 3**<br/>(고액 차단) | `555-0002로 200만 원(2000) 이체해 줘`<br/>*(또는 `transfer 2000 to 555-0002`)* | **`DENY`** | 죄송합니다. 요청하신 이체 금액이 **'고액 이체 한도 정책(High Value Transfer Limit)'의 1회 한도(100만 원 / 1,000 USD)를 초과**하여 거래를 진행할 수 없습니다. |

---

## 🧹 리소스 정리

```bash
./99-cleanup.sh
```
