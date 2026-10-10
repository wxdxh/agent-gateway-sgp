# Qwiklabs Markdown 기반 핸즈온 랩 번들(Lab Bundle) 저작 및 배포 가이드

본 문서는 **Authoring Markdown-Based Hands-on Labs (Course 615868: AUTHLAB007 ~ AUTHLAB012)** 공식 표준 규격에 따라, **에이펙스 자산운용(Apex Asset Management) 자율형 AI 에이전트 거버넌스 실습**을 GitHub 기반 **Markdown Lab Bundle (`qwiklabs-bundle/apex-agent-gateway-sgp/`)**로 구성·검증·배포하고 학습자에게 전달(Classroom)하는 전체 절차를 안내합니다.

---

## 1. Markdown Lab Bundle 디렉터리 구조 (AUTHLAB007 · AUTHLAB008)

Qwiklabs Markdown 기반 랩은 단일 폴더(**Slug**: `apex-agent-gateway-sgp`) 내에 설정 파일(`qwiklabs.yaml`), 소유자 정의(`QL_OWNER`), 지침서(`instructions/`), Terraform 스타트업 스크립트(`terraform/`), 그리고 Activity Tracking 루비 검증 코드(`assessment.yaml`, `assessments/`)를 포함하는 표준 번들 구조를 따릅니다.

```text
qwiklabs-bundle/apex-agent-gateway-sgp/
├── QL_OWNER                         # 랩 소유자(Owner) 및 공동 작업자(Collaborators) 이메일 정의
├── qwiklabs.yaml                    # Schema v2 랩 메타데이터, 리소스(gcp_project/gcp_user), 입출력 및 참조 설정
├── assessment.yaml                  # Overlay Activity Tracking 단계별 배점, 메시지, 서비스 핸들 정의
├── assessments/                     # 단계별 진행 상황 검증용 Ruby 스크립트 (ComputeV1, LoggingV2 핸들 활용)
│   ├── step_one_check.rb            # Step 1 (25점): proxy-only-subnet 및 agent-egress 게이트웨이 생성 검증
│   ├── step_two_check.rb            # Step 2 (25점): Cloud Run banking-mcp-server 배포 검증
│   ├── step_three_check.rb          # Step 3 (25점): SGP PSC IP(sgp-psc-ip) 및 엔드포인트(sgp-psc-endpoint) 검증
│   └── step_four_check.rb           # Step 4 (25점): 시맨틱 거버넌스 정책(high-value-limit) 및 감사 로그 검증
├── instructions/                    # Markdown 실습 지침서 및 이미지 디렉터리
│   ├── en.md                        # 기본 로케일(en) 호환용 지침서 (단일 # H1 제목, <ql-code-block>, <ql-infobox> 적용)
│   ├── ko.md                        # 한국어 로케일(ko) 지침서
│   └── img/                         # 지침서 내 참조 이미지 폴더 (PNG 권장, 300x600px 이하)
└── terraform/                       # Qwiklabs Terraform Startup Script (수동 압축 불필요, 폴더 직접 참조)
    ├── runtime.yaml                 # runtime: terraform / version: 1.0.1
    ├── variables.tf                 # Qwiklabs 필수 주입 변수 3종 (gcp_project_id, gcp_region, gcp_zone)
    ├── providers.tf                 # hashicorp/google 프로바이더 (v3.90.1) 설정
    ├── main.tf                      # 사전 프로비저닝 리소스 (핵심 API 13종, apex-wealth-vpc, apex-subnet, SA/IAM)
    └── outputs.tf                   # student_visible_outputs 및 지침서 동적 변수 바인딩용 출력값
```

---

## 2. 핵심 구성 파일 상세 명세

### 2.1 `QL_OWNER` (소유자 및 공동 작업자)
* 첫 번째 이메일이 **Lab Owner**, 이후 이메일들이 **Collaborators**로 지정됩니다.
* 등록되는 모든 계정은 [Qwiklabs Google Staging](https://googlestaging.qwiklabs.com/)에 계정이 존재해야 하며 최소 **Creator** 역할이 부여되어 있어야 합니다 (`User xyz@gmail.com isn't a Qwiklabs author` 오류 방지).

```text
# Owner
daehanwee@gmail.com # Lab Owner (Qwiklabs account with creator access)
# Collaborators
```

### 2.2 `qwiklabs.yaml` (Schema Version 2 표준 설정)
* **`entity_type: Lab`** 및 **`schema_version: 2`**를 명시합니다.
* **`variant: gcpd`**: 기본 Google Cloud 프로젝트 Fleet을 사용하며, 리전 인프라 생성을 위해 권장 리전 목록(`us-central1`, `us-west1`, `us-east1`, `us-east4`)을 `allowed_locations`에 지정합니다.
* **`startup_script`**: `gcp_project` 리소스 블록 내부에 `type: qwiklabs`와 `path: ./terraform`을 지정합니다.
* **`assessment`**: 루트 레벨에 `assessment: assessment.yaml`을 연결합니다.

### 2.3 `instructions/en.md` 및 `instructions/ko.md` 작성 규칙 (MD-template 준수)
1. **단일 `#` (H1) 제목 원칙**: 문서 전체에서 `#` (Heading 1)으로 시작하는 줄은 **맨 첫 줄(랩 제목) 단 1개만** 존재해야 합니다.
2. **단계별 `##` (H2) 구성**: `## Overview`, `## Setup and requirements`, `## Task 1. ...` ~ `## Task 9. ...`, `## Congratulations!` 등 모든 주요 단계는 `##`로 작성하며, 이 제목들이 좌측 목차(Table of Contents)로 렌더링됩니다.
3. **공통 Fragment (`![[/fragments/...]]`) 활용**:
   * Setup 섹션: `![[/fragments/startqwiklab]]`, `![[/fragments/gcpconsole]]`, `![[/fragments/cloudshell]]`
   * 종료 섹션: `![[/fragments/endqwiklab]]`, `![[/fragments/copyright]]`
4. **코드 블록 및 출력 블록 구분**:
   * 실행할 명령어: `<ql-code-block language="bash">...</ql-code-block>` (복사 버튼 제공 및 번호 매기기 목록 유지)
   * 터미널 실행 결과 예시: `<ql-code-block output>...</ql-code-block>` (복사 버튼 미표시, 출력 전용 스타일 적용)
5. **안내/경고 박스 (`<ql-infobox>`, `<ql-warningbox>`)**:
   * `<ql-infobox>` 내부에서 Markdown 문법이 렌더링되지 않는 현상(AUTHLAB007)을 방지하기 위해 내부 강조와 코드는 `<strong>`, `<code>` 등 HTML 태그로 작성합니다.
6. **자가 점검 퀴즈(Probes) 및 인라인 Activity Tracking**:
   * `<ql-multiple-choice-probe>`, `<ql-true-false-probe>` 태그로 학습자 이해도 점검 문제를 제공합니다.
   * 각 주요 Task 말미에 `<ql-activity-tracking step=1~4>` 태그를 배치하여 본문 내에서도 **Check my progress** 버튼을 제공합니다.

---

## 3. Terraform Startup Script 설계 및 디버깅 (AUTHLAB009)

### 3.1 사전 프로비저닝(Startup Script) vs 학습자 직접 수행 범위

| 구분 | 프로비저닝 시점 | 포함 리소스 | 설계 의도 |
| :--- | :--- | :--- | :--- |
| **Terraform Startup Script (`./terraform`)** | **Start Lab** 클릭 시 자동 생성 | • 핵심 GCP API 13종 사전 활성화<br>• 커스텀 VPC (`apex-wealth-vpc`)<br>• 리전 서브넷 (`apex-subnet`, `10.10.0.0/24`)<br>• 기본 서비스 계정 (`apex-agent-lab-sa`) 및 IAM 역할 | API 활성화 전파 지연 및 기본 VPC 생성 대기 시간을 줄여 실습자가 핵심 보안·거버넌스 아키텍처에 집중하도록 지원 |
| **학습자 Cloud Shell 실습 (Task 1 ~ Task 8)** | 실습자가 Cloud Shell에서 직접 실행 | • `proxy-only-subnet` & Network Attachment (`agent-gateway-na`)<br>• **Agent Gateway (`agent-egress`)**<br>• **Cloud Run 뱅킹 MCP 서버 (`banking-mcp-server`)**<br>• **Agent Registry** 도구/엔드포인트 등록 및 IAP Egressor 바인딩<br>• **Gemini Enterprise Agent Runtime (`gemini-3.8-flash`, Global)** 비동기 배포<br>• **SGP PSC 엔드포인트 (`sgp-psc-endpoint`)** & 프라이빗 DNS (`policy.internal.`)<br>• **AuthzExtension / AuthzPolicy / SGP 자연어 정책 (`high-value-limit`)** | 실습의 핵심 학습 목표(Objectives)인 에이전트 네트워크 거버넌스와 자연어 정책 통제를 직접 구축 및 검증 |

### 3.2 Google Staging에서 Startup Script 실행 로그 확인 방법
1. GitHub 브랜치 Push 후 커밋 상세 페이지 하단의 **GitWhisperer** 코멘트에서 Google Staging 랩 링크를 클릭합니다.
2. 우측 상단 **Edit (`.../edit`)** 아이콘을 클릭하여 편집 화면으로 이동한 뒤, 우측 상단의 **Play (`▶`)** 버튼을 눌러 랩을 시작합니다.
3. 페이지 하단 **Qwiklabs startup script** 섹션에서 **Script Runner Status**가 `IN_USE`로 바뀌면 **Script Runner Link**를 클릭합니다.
4. **Script Debugger** 화면 좌측의 **Executions**를 클릭하여 초록색 체크 표시(성공)와 **Logs** 탭의 Terraform `apply` 상세 출력을 확인합니다.

---

## 4. Activity Tracking 구성 상세 (AUTHLAB010)

전용 Ruby SDK 핸들이 없는 최신 Google Cloud 서비스(Agent Gateway, Cloud Run, SGP 정책 엔진)를 정확하게 검증하기 위해, AUTHLAB010에서 권장하는 **`project_0.ComputeV1`** 및 **`project_0.LoggingV2` (`list_entry_log_entries`)** 핸들을 조합하여 총 100점(통과 기준 `passing_percentage: 75`)의 4단계 체크포인트를 구성했습니다.

| Step | 대상 Task | 배점 | 사용 서비스 핸들 | Ruby 파일 (`method_name`) | 검증 조건 |
| :---: | :--- | :---: | :--- | :--- | :--- |
| **1** | Task 2 (Agent Gateway 배포) | 25 | `project_0.ComputeV1`<br>`project_0.LoggingV2` | `step_one_check` | `proxy-only-subnet` 서브넷 존재 여부 및 `networkservices.googleapis.com`의 `agentGateways/agent-egress` 감사 로그 확인 |
| **2** | Task 3 (Cloud Run MCP 서버 배포) | 25 | `project_0.LoggingV2` | `step_two_check` | `run.googleapis.com`의 `services/banking-mcp-server` 배포 감사 로그 확인 |
| **3** | Task 6 (SGP PSC 엔드포인트 구성) | 25 | `project_0.ComputeV1` | `step_three_check` | `sgp-psc-ip` 내부 고정 IP 예약 및 `sgp-psc-endpoint` 전달 규칙(Forwarding Rule) 존재 여부 확인 |
| **4** | Task 7~8 (SGP 정책 및 3-Turn 검증) | 25 | `project_0.LoggingV2` | `step_four_check` | `high-value-limit` 정책 생성 로그 또는 `logs/semantic-governance-policy` 감사 로그 존재 여부 확인 |

---

## 5. GitHub 브랜치 작업 · GitWhisperer 디버깅 및 PR 배포 절차 (AUTHLAB011)

### 5.1 로컬 리포지토리에서 브랜치 생성 및 Push
1. **GitHub Desktop**을 열고 대상 리포지토리(예: `hol-creation` 또는 타겟 콘텐츠 리포지토리)를 선택합니다.
   * 로컬 [`/Users/dhwee/Documents/hol-creation/labs/apex-agent-gateway-sgp`](file:///Users/dhwee/Documents/hol-creation/labs/apex-agent-gateway-sgp) 경로에도 동일한 번들 사본이 준비되어 있습니다.
2. 상단 **Current Branch** 드롭다운을 클릭하고 고유한 작업 브랜치명(예: `feat-apex-agent-gateway-sgp`)을 입력한 뒤 **Create new branch** → **Publish branch**를 클릭합니다.
3. 변경 사항을 확인하고 좌측 하단에 커밋 메시지를 입력한 뒤 **Commit** 및 **Push origin**을 클릭합니다.

### 5.2 GitWhisperer 사전 검증 체크리스트
본 번들은 GitWhisperer가 검사하는 아래 모든 항목을 사전 통과하도록 검증되었습니다:
* [x] **YAML 문법 및 2칸 들여쓰기**: `qwiklabs.yaml`, `assessment.yaml`, `terraform/runtime.yaml` (`python3 -c "import yaml; ..."` 검증 완료)
* [x] **Terraform 유효성 검사**: `hashicorp/google` `v3.90.1` 기준 `terraform init -backend=false && terraform validate` 통과 (`Success! The configuration is valid.`)
* [x] **Ruby 문법 및 함수명 일치**: `assessments/step_*_check.rb` 4종 모두 `ruby -c` (`Syntax OK`) 및 `assessment.yaml`의 `method_name`과 함수명 일치
* [x] **단일 `#` (H1) 제목**: `instructions/en.md`, `instructions/ko.md` 모두 1행에만 `#` 제목이 존재하며 나머지 모든 Step은 `##` (H2) 사용
* [x] **유효한 Fleet 및 Output 참조**: `variant: gcpd` 사용, `student_visible_outputs`의 모든 참조(`project_0.*`, `user_0.*`, `project_0.startup_script.*`)가 실제 정의와 일치

### 5.3 Pull Request 생성 및 정식 배포
1. GitHub 웹 페이지에서 작업 브랜치의 최신 커밋 상세 페이지 하단에 **`Everything looks good to go.`** 메시지와 Google Staging 프리뷰 링크가 표시되는지 확인합니다.
2. Staging 프리뷰 링크를 열어 브랜치 버전의 랩을 실행하고 Startup Script와 Activity Tracking이 100% 점수로 동작하는지 확인합니다.
3. 검증이 완료되면 GitHub에서 **`base: main` ← `compare: feat-apex-agent-gateway-sgp`**로 **New pull request**를 생성합니다.
4. 우측 메뉴의 **Assignees**(및 **Reviewers**)에 리포지토리 관리자 그룹인 **`Qwiklabs-Sharing`**을 지정합니다.
5. PR이 승인되어 `main` 브랜치에 병합되면 [Google Staging](https://googlestaging.qwiklabs.com/)의 **Authoring > Labs** 목록에 브랜치명 꼬리표가 없는 정식 사본으로 등록됩니다.

---

## 6. 학습자에게 랩 전달하기: Classroom Template 및 Classroom 운영 (AUTHLAB012)

정식 배포된 랩을 워크숍이나 강의(ILT) 형태로 학습자에게 전달할 때는 **Classroom Template**과 **Classroom**을 생성합니다.

1. **Classroom Template 생성 (`Google Staging > Authoring > Classroom Templates > +`)**:
   * **Name**, **Description**을 입력하고 **Fraud Protection**과 **Enabled** 체크박스를 반드시 모두 선택합니다.
   * 필요 시 **Student Instruction** / **Trainer Instruction** 자료를 추가하고, 실습 목록에서 본 랩을 선택한 뒤 **Create Classroom template**을 클릭합니다.
   * 생성된 템플릿을 실제 교육 전달 플랫폼(Delivery Platform)으로 퍼블리시합니다.
2. **Classroom 생성 및 운영 (`Delivery Platform > Classrooms > +`)**:
   * **주의:** 실제 수강생 대상 교육은 절대 Google Staging에서 실행하지 말고 반드시 정식 Delivery Platform에서 생성하세요.
   * 퍼블리시된 Classroom Template을 검색해 선택한 뒤 **Public Classroom** 또는 **Virtual Classroom**을 선택합니다.
   * 강사(**Trainer**), 시작/종료 일정, **Location (`Online` 등)**, **Timezone**, **Lab Access**, **Hot labs** 수량을 지정하고 **Create Classroom**을 클릭합니다.
3. **랩 활성화 및 수강생 등록**:
   * Classroom의 **Labs** 탭 상단에서 **Activate all labs** 아이콘을 클릭하여 수강생이 랩을 시작할 수 있도록 활성화합니다.
   * **Students** 탭에서 수강생의 개별 이메일 주소를 추가(또는 CSV 일괄 업로드, 도메인 와일드카드 사용 금지)하고, 수업 중 진행 상태 관리 및 종료 후 **Download Assessment Record (CSV)**로 점수를 다운로드할 수 있습니다.
