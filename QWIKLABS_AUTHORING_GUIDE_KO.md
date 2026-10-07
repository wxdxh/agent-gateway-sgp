# **Google Docs 및 Terraform Startup Script 기반 Qwiklabs 저작(Authoring) 가이드**

본 문서는 Qwiklabs 공식 저작 과정(**AUTHLAB004: Using Startup Scripts to Stage Resources in a Google Docs-Based Hands-on Lab**)의 표준 규격에 맞춰, **에이펙스 자산운용(Apex Asset Management) 엔터프라이즈 AI 에이전트 거버넌스** 실습을 **Google Docs 매뉴얼 + Terraform Startup Script(`terraform.zip`)** 조합으로 Qwiklabs Staging 환경에 등록·배포하는 전 과정을 안내합니다.

---

## **1. 사전 프로비저닝(Resource Staging) 설계 전략**

Qwiklabs 환경에서 학습자가 **Start Lab** 버튼을 클릭했을 때 백그라운드에서 실행되는 **Terraform Startup Script(`terraform.zip`)**와, 학습자가 **Cloud Shell**에서 직접 수행하는 **핵심 실습(Task 1 ~ Task 9)**의 역할을 다음과 같이 분리하여 학습 몰입도와 안정성을 극대화합니다.

| 구분 | 실행 주체 및 시점 | 포함 리소스 및 작업 | 설계 의도 |
| :--- | :--- | :--- | :--- |
| **사전 프로비저닝 (Staging)** | **Qwiklabs Startup Script (`terraform.zip`)**<br>*(Start Lab 클릭 시 자동 실행)* | • **핵심 GCP API 13종** 사전 활성화<br>• 전용 커스텀 VPC(`apex-wealth-vpc`) 생성<br>• 리전 서브넷(`apex-subnet`, `10.10.0.0/24`) 생성<br>• 실습 기본 서비스 계정(`apex-agent-lab-sa`) 및 IAM 권한 부여 | API 활성화 전파 대기 시간(약 3~4분) 및 기초 네트워크 생성 시간을 단축하고, 초기 권한 오류를 방지합니다. |
| **핵심 핸즈온 실습 (Lab Tasks)** | **학습자 (Google Cloud Shell)**<br>*(Task 1 ~ Task 9 직접 수행)* | • Network Services Identity 및 전용 프록시 서브넷 구성<br>• **Agent Gateway (`agent-egress`)** 배포<br>• **Cloud Run MCP 서버 (`banking-mcp-server`)** 배포 및 등록<br>• **Gemini Enterprise ADK 에이전트 (`gemini-3.8-flash`, Global Endpoint)** 비동기 배포<br>• **SGP PSC 엔드포인트 + Cloud DNS (`policy.internal.`)** 구성<br>• **SGP CEL 정책 (`amount <= 1000.0`, 100만 원 한도)** 생성 및 검증 | 아키텍처의 핵심인 양방향 제로 트러스트 거버넌스(Agent Gateway + SGP + ADK)는 학습자가 직접 구축하고 검증하도록 유지합니다. |

> **참고 (완벽한 멱등성 보장):** 레포지토리의 `env.sh`, `01-setup-env.sh`, `02-setup-agent-gateway.sh`는 Qwiklabs Startup Script가 미리 생성해 둔 `apex-wealth-vpc` 및 `apex-subnet`을 자동으로 최우선 감지하여 재사용하며, Startup Script가 없는 일반 GCP 프로젝트에서 실행하더라도 동일하게 생성·동작하도록 설계되어 있습니다.

---

## **2. Qwiklabs Terraform Startup Script 파일 구조 해설**

본 레포지토리의 `qwiklabs-terraform/` 디렉토리와 루트의 `terraform.zip` 파일에는 Qwiklabs Startup Script 표준 규격을 준수하는 5개의 필수 파일이 포함되어 있습니다.

```text
qwiklabs-terraform/          (압축 파일: ./terraform.zip)
├── main.tf                  # 사전 프로비저닝할 GCP 인프라 정의 (API, VPC/Subnet, SA/IAM)
├── variables.tf             # Qwiklabs 플랫폼이 자동 주입하는 필수 변수 3종 선언
├── providers.tf             # Google Terraform Provider 버전 및 프로젝트/리전 바인딩
├── outputs.tf               # Qwiklabs Lab Details 패널에 노출할 환경 출력값 정의
└── runtime.yaml             # Qwiklabs Script Runner용 Terraform 런타임 버전 명시 (필수)
```

### **2.1 `runtime.yaml` (필수 런타임 정의)**
Qwiklabs Script Runner가 사용할 Terraform 버전을 지정합니다.
```yaml
runtime: terraform
version: 1.0.1
```

### **2.2 `variables.tf` (Qwiklabs 필수 자동 주입 변수)**
Qwiklabs 플랫폼이 랩 시작 시점에 자동으로 값을 채워주는 3가지 필수 변수(`gcp_project_id`, `gcp_region`, `gcp_zone`)를 선언합니다.
```hcl
variable "gcp_project_id" {
  type        = string
  description = "The GCP project ID to apply this config to."
}

variable "gcp_region" {
  type        = string
  description = "The GCP region to apply this config to."
  default     = "us-central1"
}

variable "gcp_zone" {
  type        = string
  description = "The GCP zone to apply this config to."
  default     = "us-central1-a"
}
```

### **2.3 `providers.tf` (Provider 버전 고정)**
예기치 않은 호환성 문제를 방지하기 위해 Qwiklabs 권장 사항에 따라 `google` 정식 프로바이더의 정확한 버전을 명시합니다.
```hcl
terraform {
  required_providers {
    google = {
      version = "3.90.1"
    }
  }
}

provider "google" {
  project = var.gcp_project_id
  region  = var.gcp_region
  zone    = var.gcp_zone
}
```

### **2.4 `main.tf` (기반 인프라 사전 스테이징)**
랩이 시작될 때 핵심 GCP API 13종을 활성화하고, 에이펙스 자산운용 전용 VPC(`apex-wealth-vpc`) 및 서브넷(`apex-subnet`), 기본 서비스 계정(`apex-agent-lab-sa`)을 생성합니다.
```hcl
data "google_project" "project" {
  project_id = var.gcp_project_id
}

locals {
  required_apis = [
    "compute.googleapis.com",
    "networksecurity.googleapis.com",
    "networkservices.googleapis.com",
    "dns.googleapis.com",
    "iam.googleapis.com",
    "iap.googleapis.com",
    "aiplatform.googleapis.com",
    "run.googleapis.com",
    "cloudbuild.googleapis.com",
    "artifactregistry.googleapis.com",
    "storage.googleapis.com",
    "cloudtrace.googleapis.com",
    "logging.googleapis.com"
  ]

  lab_iam_roles = [
    "roles/aiplatform.user",
    "roles/run.admin",
    "roles/cloudbuild.builds.editor",
    "roles/dns.admin"
  ]
}

resource "google_project_service" "required_apis" {
  for_each           = toset(local.required_apis)
  project            = var.gcp_project_id
  service            = each.value
  disable_on_destroy = false
}

resource "google_compute_network" "apex_wealth_vpc" {
  name                    = "apex-wealth-vpc"
  auto_create_subnetworks = false
  project                 = var.gcp_project_id
  description             = "VPC network for Apex Asset Management Agent Gateway and SGP lab"
  depends_on              = [google_project_service.required_apis]
}

resource "google_compute_subnetwork" "apex_subnet" {
  name          = "apex-subnet"
  ip_cidr_range = "10.10.0.0/24"
  region        = var.gcp_region
  network       = google_compute_network.apex_wealth_vpc.id
  project       = var.gcp_project_id
  description   = "Regional subnet for Agent Gateway Network Attachment and SGP PSC endpoint"
}

resource "google_service_account" "apex_lab_sa" {
  account_id   = "apex-agent-lab-sa"
  display_name = "Apex Asset Management Lab Service Account"
  project      = var.gcp_project_id
  depends_on   = [google_project_service.required_apis]
}

resource "google_project_iam_member" "apex_lab_sa_roles" {
  for_each = toset(local.lab_iam_roles)
  project  = var.gcp_project_id
  role     = each.value
  member   = "serviceAccount:${google_service_account.apex_lab_sa.email}"
}
```

### **2.5 `outputs.tf` (Environment Outputs 노출)**
Terraform이 생성한 리소스 정보를 Qwiklabs 좌측 **Lab details** 패널에 표시할 수 있도록 출력값을 정의합니다.
```hcl
output "gcp_project_id" {
  value       = var.gcp_project_id
  description = "The GCP Project ID provisioned for the Apex Asset Management lab."
}

output "gcp_region" {
  value       = var.gcp_region
  description = "The default GCP region for Agent Gateway, Cloud Run MCP, and SGP resources."
}

output "vpc_network_name" {
  value       = google_compute_network.apex_wealth_vpc.name
  description = "Pre-provisioned VPC network name (apex-wealth-vpc)."
}

output "vpc_subnet_name" {
  value       = google_compute_subnetwork.apex_subnet.name
  description = "Pre-provisioned regional subnet name (apex-subnet)."
}

output "lab_service_account" {
  value       = google_service_account.apex_lab_sa.email
  description = "Pre-provisioned service account email for the lab."
}
```

### **2.6 `terraform.zip` 번들 생성 방법 (수정 시 재압축 명령어)**
> **주의:** Qwiklabs에 업로드하는 `terraform.zip`은 **상위 디렉토리(폴더) 없이 5개의 파일만 압축 파일의 최상위(Root)에 위치**해야 합니다(`-j` 옵션 사용).

```bash
rm -f terraform.zip
zip -j terraform.zip \
  qwiklabs-terraform/main.tf \
  qwiklabs-terraform/variables.tf \
  qwiklabs-terraform/providers.tf \
  qwiklabs-terraform/outputs.tf \
  qwiklabs-terraform/runtime.yaml
```

---

## **3. Step-by-Step: Google Docs 및 Startup Script로 Qwiklabs 랩 등록하기**

### **Task 1. 서식 깨짐 없는 Google Docs 매뉴얼 문서 생성 및 권한 공유**

일반 마크다운(`.md`) 파일의 원문을 그대로 복사하여 Google Docs에 일반 붙여넣기(`Ctrl+V` / `Cmd+V`)하면 `#`, `**`, ```` ``` ```` 기호가 일반 텍스트로 노출되거나, Qwiklabs Google Docs 파서(`qwiklabs-publisher@google.com`)가 요구하는 **1x1 단일 셀 표(Code Block Table)** 서식이 누락됩니다. 이를 완벽히 해결하기 위해 아래 **3가지 서식 무손실 방법** 중 하나를 선택하여 Google Docs 문서를 준비하세요.

#### **방법 A (가장 권장 · 서식 깨짐 0%): Google Docs 전용 `.docx` 파일 업로드 및 변환**
본 레포지토리의 **[`QWIKLABS_CLOUD_SHELL_KO.docx`](./QWIKLABS_CLOUD_SHELL_KO.docx)** 파일은 모든 제목(`Heading 1`, `Heading 2`), 번호 매기기, 표, 그리고 Qwiklabs 표준 **1x1 회색 코드 블록 표(`Courier New`, `#F3F3F3` 배경)** 및 **1x1 파란색 안내 상자 표(`#E8F0FE` 배경)**가 네이티브 문서 규격으로 미리 변환되어 있습니다.
1. [`QWIKLABS_CLOUD_SHELL_KO.docx`](https://github.com/wxdxh/agent-gateway-sgp/raw/main/QWIKLABS_CLOUD_SHELL_KO.docx) 파일을 로컬 컴퓨터에 다운로드합니다.
2. 개인 또는 기업용 Google 계정으로 [Google Drive](https://drive.google.com/)에 접속한 뒤 **새로 만들기(+) > 파일 업로드**를 클릭하여 `QWIKLABS_CLOUD_SHELL_KO.docx`를 업로드합니다.
3. 업로드된 파일을 더블클릭하여 **Google 문서로 열기(Open with Google Docs)**를 선택한 다음, 상단 메뉴에서 **파일(File) > Google 문서로 저장(Save as Google Docs)**을 클릭합니다.
   > **주의:** Qwiklabs에 등록할 때는 `.docx` 뷰어 상태가 아니라 변환된 **네이티브 Google Docs 문서**의 URL을 사용해야 합니다.

#### **방법 B (원클릭 클립보드 서식 복사): 웹 도우미 페이지(`gdocs-paste.html`)에서 원클릭 복사 후 `Ctrl+V`**
1. 브라우저에서 **[Google Docs 서식 무손실 복사 도우미 (`gdocs-paste.html`)](https://agent-gateway-codelab-1080321871308.us-central1.run.app/gdocs-paste.html)** 페이지를 엽니다.
2. 상단 툴바의 **[📋 Google Docs 서식 그대로 원클릭 복사]** 버튼을 클릭합니다. (일반 텍스트가 아닌 `text/html` 서식 데이터가 클립보드에 복사됩니다.)
3. 빈 [Google Docs](https://docs.google.com/) 문서를 새로 열고 **`Ctrl+V` (Mac은 `Cmd+V`)**를 누르면, `Heading 1 / 2` 제목 계층과 **1x1 회색 코드 블록 표(`Courier New`)**가 깨짐 없이 그대로 붙여넣어집니다.

#### **방법 C (Markdown 원본 사용 시): Google Docs의 `마크다운에서 붙여넣기` 기능 사용**
* 만약 [`QWIKLABS_CLOUD_SHELL_KO.md`](./QWIKLABS_CLOUD_SHELL_KO.md) 원본 텍스트를 직접 붙여넣으려면, 반드시 Google Docs 상단 메뉴 **도구(Tools) > 환경설정(Preferences)**에서 **'마크다운 사용(Enable Markdown)'**을 먼저 체크한 뒤, 문서 화면에서 **우클릭 > 마크다운에서 붙여넣기(Paste from Markdown)**를 선택하세요. (본 `.md` 파일에서도 Google Docs 파서를 깨뜨리는 `GSPxxxx`, `&nbsp;`, `mermaid`, 중첩 인용구 블록을 모두 제거해 두었습니다.)

#### **공통 마무리: `qwiklabs-publisher@google.com` 공유**
1. 생성된 Google Docs 문서 내에 `[[ import labmanuallogo ]]`, `[[ import startqwiklab ]]`, `[[ import gcpconsole ]]`, `[[ import cloudshell ]]`, `[[ import TrainingCertificationOverview ]]`, `[[ import copyright ]]` 매크로 문자열이 그대로 포함되어 있는지 확인합니다.
2. 우측 상단의 **공유(Share)** 버튼을 클릭하고 다음 이메일 주소를 추가하여 공유합니다:
   ```text
   qwiklabs-publisher@google.com
   ```
   > **참고:** `qwiklabs-publisher@google.com`에 공유해야 Qwiklabs Publisher 서비스가 Google Docs 문서를 읽어 웹 실습 매뉴얼로 변환할 수 있습니다.
3. 브라우저 주소창에서 해당 Google Docs 문서의 **URL**을 복사해 둡니다.

---

### **Task 2. Google Staging에서 신규 Lab 생성 및 Google Docs 연동**

1. Creator 권한이 있는 계정으로 [Google Staging (googlestaging.qwiklabs.com)](https://googlestaging.qwiklabs.com/labs)에 로그인합니다.
2. 좌측 상단 **Menu (☰)** > **Authoring**을 클릭합니다.
3. 우측 상단의 **Add (+)** 버튼을 클릭하여 새 랩을 추가합니다.
4. **Create new lab** 페이지에서 **Google Cloud Platform**을 선택합니다.
5. 속성 대화상자에서 다음 값을 입력하고 **Create Lab**을 클릭합니다:

| Property | Value |
| :--- | :--- |
| **Title** | `엔터프라이즈 AI 에이전트 거버넌스: Agent Gateway와 Semantic Governance Policy` *(고유한 제목)* |
| **Description** | `에이펙스 자산운용 시나리오를 바탕으로 Agent Gateway, Cloud Run MCP 서버, Gemini Enterprise ADK 에이전트(gemini-3.8-flash), SGP를 연동하여 제로 트러스트 런타임 거버넌스를 구축하는 실습입니다.` |
| **Level** | `Intermediate` (또는 `Introductory`) |
| **Price** | `0` |
| **Max Duration** | `90` (minutes) |

6. 생성된 랩의 **Edit** 화면 좌측 패널에서 **Instructions**를 클릭합니다.
7. 옵션에서 **Google Doc**이 선택된 상태를 유지하고, **Instruction URL** 입력란에 **Task 1**에서 복사한 Google Docs URL을 붙여넣은 뒤 **Submit**을 클릭합니다.
   * 만약 가져오기 직후 오류가 표시되면 상단의 **Refresh Instructions**를 클릭합니다.
8. 우측 상단의 **Preview (👁️)** 아이콘을 클릭하여 학습자에게 보이는 매뉴얼 화면이 정상적으로 렌더링되는지 확인한 후, 다시 **Edit lab (✏️)** 아이콘을 클릭해 편집 화면으로 돌아옵니다.

---

### **Task 3. Lab Resources (`project_0`) 및 Startup Script (`terraform.zip`) 구성**

1. 좌측 패널에서 **Lab Resources**를 클릭하고 기본 생성된 `project_0`와 `user_0` 리소스를 확인합니다.
2. **`project_0`** Resource ID를 클릭하여 설정 화면을 엽니다:
   * **Allowed Locations:** `us-central1`을 기본 리전으로 추가합니다(필요 시 `us-west1`, `us-east1`, `us-east4` 추가 가능하나, 본 실습의 SGP 및 Agent Gateway 테스트는 `us-central1` 기준).
   * **Startup Scripts:** **Choose File** 버튼을 클릭하고 본 레포지토리 루트에 준비된 **`terraform.zip`** 파일을 선택하여 업로드합니다.
   * **Update Lab resource** 버튼을 클릭하여 저장합니다.
3. 좌측 패널에서 **Environment Outputs**를 클릭합니다:
   * **To add the typical default environment outputs click here** 링크를 클릭하여 기본 출력값 4종을 추가합니다:
     * `Open Console` -> 라벨을 **`Open Google Cloud console`**로 변경
     * `Username`
     * `Password`
     * `Project ID`
   * (선택 사항) Startup Script(`outputs.tf`)에서 정의한 출력값을 Lab details 패널에 함께 표시하려면 다음 출력 매핑을 추가할 수 있습니다:
     * `project_0.startup_script.gcp_region` (Label: `Region`)
     * `project_0.startup_script.vpc_network_name` (Label: `VPC Network`)
     * `project_0.startup_script.vpc_subnet_name` (Label: `VPC Subnet`)
   * **Update Environment Outputs** 버튼을 클릭하여 저장합니다.

---

### **Task 4. Script Runner로 Terraform Startup Script 실행 및 디버깅**

랩을 학습자에게 공개하기 전에 Qwiklabs 내장 **Script Runner**를 통해 `terraform.zip`이 오류 없이 프로비저닝되는지 검증합니다.

1. 랩 **Edit** 화면 우측 상단에서 **Startup Lab Environment (▶️)** 아이콘을 클릭합니다. 잠시 후 **Status** 페이지가 열립니다.
2. 페이지 하단의 **Qwiklabs Startup Script** 섹션으로 스크롤합니다.
3. **Script Runner Status**가 `IN_USE`로 표시되면 **Script Runner Link** 하이퍼링크를 클릭합니다. 새 탭에서 Script Runner UI가 열립니다.
4. 좌측 패널에서 **Executions**를 클릭하여 Terraform 실행 내역을 확인합니다:
   * 실행 상태에 **녹색 체크 마크(✅)**가 표시되는지 확인합니다.
   * 해당 실행 항목을 클릭하여 3개의 탭을 점검합니다:

| 탭 (Tab) | 확인 내용 (Description) |
| :--- | :--- |
| **Overview** | Terraform `init` / `plan` / `apply` 전체 실행 상태 및 소요 시간 확인 |
| **Logs** | 13개 API 활성화, `apex-wealth-vpc`, `apex-subnet`, `apex-agent-lab-sa` 생성 로그 및 Outputs 결과 확인 |
| **Files** | 업로드된 `main.tf`, `variables.tf`, `providers.tf`, `outputs.tf`, `runtime.yaml` 원본 코드 확인 |

5. 검증이 완료되면 Script Debugger 브라우저 탭을 닫고 **Status** 페이지 하단 좌측의 **Back**을 클릭하여 **Edit** 페이지로 돌아옵니다.
6. 우측 상단의 **Stop Lab Environment (⏹️)**를 클릭한 뒤 **Submit**을 눌러 테스트 환경을 종료합니다.

---

### **Task 5. (선택 사항) Git용 Markdown 번들 내보내기**

Google Docs로 작성하고 `terraform.zip`을 연결한 랩 전체 구성을 Git 저장소용 번들(`hol-lab.zip`)로 백업하거나 이관할 수 있습니다.

1. 랩 **Edit** 페이지 우측 상단의 **더보기(⋮)** 아이콘을 클릭합니다.
2. **Download this lab as Markdown for Git**을 클릭하면 Google Docs 지침과 `terraform.zip` 설정이 통합된 ZIP 아카이브가 로컬 컴퓨터로 다운로드됩니다.
