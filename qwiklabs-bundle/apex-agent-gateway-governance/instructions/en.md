# Govern Agentic Workloads with Gemini Enterprise Agent Platform and Agent Gateway (IAP & Model Armor)

## Overview

For autonomous AI agents to deliver real business value in the enterprise, they must connect to internal document management systems, external financial verification APIs, and corporate email servers. While the **Model Context Protocol (MCP)** provides a standardized JSON-RPC interface for agents to invoke external tools, it also introduces three critical governance challenges for enterprise security teams and platform engineers:

1. **Lack of Fine-Grained Tool-Level Access Control**: Granting network connectivity and invocation permissions (`roles/run.invoker`) to an MCP server allows an agent to invoke not only safe read-only tools (`search_emails`, `read_email`) but also high-risk state-mutating or data-exfiltrating tools (`send_email`).
2. **Risk of Sensitive PII Leaking into LLM Context**: When legacy databases or document management systems return raw responses containing high-risk personally identifiable information (PII) such as **Korean Resident Registration Numbers (`KOREA_RRN`)** or **US Social Security Numbers (`US_SOCIAL_SECURITY_NUMBER`)**, those values are exposed directly in the LLM prompt context and conversation logs.
3. **Black-Box Agent-to-Tool Communication and Lack of Observability**: Without a centralized control point, it is difficult to track which MCP tools an agent invokes, where latency occurs, and which security policies blocked or redacted a request.

In this lab, based on the **Apex Financial Group Automated Mortgage Underwriting Agent (`mortgage-agent`)** scenario, you will implement centralized security governance and unified observability by combining **Google Cloud Agent Gateway** with **Service Extensions (IAP and Model Armor + Cloud DLP)**—all without modifying the business logic of the backend MCP servers.

![Apex Financial Group Agent Gateway Governance Overall Architecture](img/00-overall-architecture.png)

---

### Lab Scenario: Apex Financial Group Mortgage Underwriting Agent

An underwriter at Apex Financial Group uses **`mortgage-agent`**, running on Vertex AI Agent Engine, to evaluate whether co-applicants **Minjun Kim and Seoyeon Lee** qualify for a new 2026 residential mortgage. To complete the underwriting assessment, the agent communicates with three backend MCP servers:

| MCP Server Name | Business Role | Exposed MCP Tools | Agent Gateway Topology | Applied Governance Policy |
| :--- | :--- | :--- | :--- | :--- |
| **`legacy-dms`** | Legacy Document Management System (2023/2024 tax return lookup) | `search_tax_returns`, `get_document_metadata` | **Client-Side (`agent-egress`)**<br>`AGENT_TO_ANYWHERE` | **Model Armor + Cloud DLP (`CONTENT_AUTHZ`)**:<br>Automatically redacts Korean RRN (`850315-1234566` ➔ `[KOREA_RRN]`) and US SSN (`323-45-6789` ➔ `[US_SOCIAL_SECURITY_NUMBER]`) in responses |
| **`income-verification`** | External Income & Employment Verification API (2026 DTI calculation) | `verify_income` | **Client-Side (`agent-egress`)**<br>`AGENT_TO_ANYWHERE` | **Model Armor + Cloud DLP (`CONTENT_AUTHZ`)**:<br>Bidirectional redaction of Korean RRN (`[KOREA_RRN]`) and US SSN (`[US_SOCIAL_SECURITY_NUMBER]`) in external API requests and responses |
| **`corporate-email`** | Internal Corporate Email & Underwriting Guidelines Server (2026 45% DTI cap notice) | `search_emails`, `read_email`, `send_email` | **Server-Side (`cloud-run`)**<br>`self_managed` ingress protection | **IAP + CEL (`REQUEST_AUTHZ`)**:<br>Allows `search_emails` and `read_email`, but blocks `send_email` tool calls (validated in `DRY_RUN` mode before switching to `ENFORCED`) |

---

### Key Architectural Concepts

#### 1. Two Deployment Topologies of Agent Gateway: Client-Side (`agent-egress`) vs. Server-Side (`cloud-run`)
* **Client-Side Gateway (`google_managed.governed_access_path = "AGENT_TO_ANYWHERE"`)**: Acts as a forward proxy on the agent's outbound (egress) path. It intercepts agent traffic destined for third-party SaaS APIs or legacy systems (`legacy-dms`, `income-verification`) that you cannot directly modify, applying auditing and DLP redaction.
* **Server-Side Gateway (`self_managed.resource_uri`)**: Acts as a reverse proxy in front of internal Cloud Run MCP workloads (`corporate-email`). It enforces caller identity verification and fine-grained tool-level authorization (IAP CEL) on all inbound MCP requests.

![Networking Modes Comparison: Default Public Ingress vs. Private Networking](img/01-networking-modes.png)

#### 2. Dual Security Controls via Service Extensions: IAP (`REQUEST_AUTHZ`) & Model Armor (`CONTENT_AUTHZ`)
Agent Gateway chains Google Cloud security services across two execution phases on its Envoy-based data plane:
* **`REQUEST_AUTHZ` Phase — Identity-Aware Proxy (IAP) + CEL**: Inspects MCP JSON-RPC request headers and payloads (`request.mcp.method`, `request.mcp.tool.name`) to allow or deny specific tool invocations. It supports **`DRY_RUN` mode**, enabling you to audit policy violations in production traffic without disruption before transitioning to **`ENFORCED` mode**.
* **`CONTENT_AUTHZ` Phase — Model Armor + Cloud DLP (Sensitive Data Protection)**: Scans MCP request and response payloads (`structuredContent`) in real time to block prompt injection attacks and redact Korean Resident Registration Numbers (`KOREA_RRN`) and US Social Security Numbers (`US_SOCIAL_SECURITY_NUMBER`) into `[KOREA_RRN]` and `[US_SOCIAL_SECURITY_NUMBER]` tokens.

![IAP CEL and Model Armor DLP Dual Security Control Flow](img/02-iap-cel-model-armor.png)

---

### Objectives

In this lab, you will learn how to:

* Build and push three FastMCP backend server containers (`legacy-dms`, `income-verification`, `corporate-email`) to Artifact Registry using Skaffold and Cloud Build.
* Provision three client-side (`agent-egress`) and server-side (`cloud-run`) Agent Gateways along with a custom Cloud Monitoring dashboard using Terraform.
* Configure Cloud DLP `InspectTemplate` / `DeidentifyTemplate` (`KOREA_RRN`, `US_SOCIAL_SECURITY_NUMBER`) and Model Armor templates to redact sensitive PII in MCP responses in real time.
* Deploy an IAP Common Expression Language (CEL) policy in `DRY_RUN` mode first, then switch it to `ENFORCED` mode to block unauthorized outbound emails (`send_email`) in real time.
* Verify end-to-end agent governance using the Vertex AI Agent Engine Playground, Cloud Monitoring dashboards, Cloud Trace, and Cloud Logging.

---

## Setup and Requirements

### Before you click the Start Lab button

1. Click the **Start Lab** button at the top left of the Qwiklabs page.
2. Once the lab environment is ready, review the **Project ID**, **Region**, **Username**, and **Password** in the left panel.
3. Click **Open Google Cloud console** to sign in to the Google Cloud Console in an Incognito window.
4. Click the terminal icon (**Activate Cloud Shell**) in the top-right corner of the console to open Cloud Shell.

> **Note**: The Qwiklabs startup script pre-enables 20 required Google Cloud APIs and provisions the foundational service identities (Vertex AI, Cloud DLP) in the background.

---

## Task 1. Configure Environment Variables and Clone the Lab Repository

In Cloud Shell, configure your project environment variables and clone the lab repository containing the mortgage underwriting scenario.

### 1. Initialize Environment Variables and Verify Authentication

Run the following commands in your Cloud Shell terminal:

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

### 2. Clone the Lab Source Repository

Run the following commands to clone the lab repository and inspect its directory structure:

```bash
cd ~
rm -rf ~/agent-gateway-governance
git clone https://github.com/wxdxh/agent-gateway-governance.git ~/agent-gateway-governance 2>/dev/null || \
  git clone -b governance https://github.com/wxdxh/agent-gateway-sgp.git ~/agent-gateway-governance

cd ~/agent-gateway-governance
ls -la
```

The repository contains the following core directories:

* `src/legacy-dms/`: FastMCP server providing tax return search and document metadata (contains Korean RRN `850315-1234566` and US SSN records).
* `src/income-verification-api/`: FastMCP server that verifies applicant income and calculates the 2026 DTI ratio.
* `src/corporate-email/`: FastMCP server providing internal underwriting guideline email search/read tools (`search_emails`, `read_email`) and an outbound email tool (`send_email`).
* `src/mortgage-agent/`: Google ADK mortgage underwriting agent and deployment script (`deploy_agent.py`).
* `terraform/`: Terraform module that provisions Cloud Run, Agent Gateway, IAP, Model Armor/DLP, Vertex AI Agent Engine, and the Cloud Monitoring dashboard.
* `scripts/grant_agent_mcp_egress.sh`: Script that grants Agent Gateway invocation permissions (`roles/networkservices.agentGatewayUser`) and Cloud Run invoker permissions (`roles/run.invoker`) to the deployed Agent Identity.

---

## Task 2. Inspect the Backend MCP Server Code and Build Container Images

For Agent Gateway's Model Armor (`CONTENT_AUTHZ`) integration to accurately redact sensitive PII from MCP tool responses, it is important to understand how the MCP servers return data.

### 1. Inspect the FastMCP `structuredContent` Return Structure

Run the following command to inspect the tool return structure in `src/legacy-dms/server.py`:

```bash
sed -n '95,145p' ~/agent-gateway-governance/src/legacy-dms/server.py
```

* By default, when FastMCP serializes a Python dictionary return value, it populates both a plain-text array (`content`) and a structured JSON block (`structuredContent`).
* Currently, **Agent Gateway's Model Armor integration inspects and redacts only the `structuredContent` field of MCP responses**. If raw strings remain in the `content` array, unredacted RRNs or SSNs could leak to the agent. Therefore, all MCP tools in this lab explicitly return `ToolResult(content=[], structured_content=...)`.

### 2. Create the Artifact Registry Repository

First, use Terraform to create the Artifact Registry repository (`mcp-servers`) that will store the container images:

```bash
cd ~/agent-gateway-governance/terraform
terraform init

terraform apply \
  -target=google_project_service.apis \
  -target=google_artifact_registry_repository.mcp_servers \
  -var="project_id=${PROJECT_ID}" \
  -var="region=${REGION}" \
  -auto-approve
```

### 3. Build and Push the Three MCP Server Images with Skaffold

Return to the repository root and run `skaffold build` to build and push the `legacy-dms`, `income-verification`, and `corporate-email` container images to Artifact Registry:

```bash
cd ~/agent-gateway-governance
export REPO="${REGION}-docker.pkg.dev/${PROJECT_ID}/mcp-servers"

skaffold build --default-repo="${REPO}"
```

Once the build completes, verify that all three images are registered in Artifact Registry:

```bash
gcloud artifacts docker images list "${REPO}" --include-tags
```

<ql-activity-tracking step=1>
Check Artifact Registry and MCP Server Container Builds
</ql-activity-tracking>

---

## Task 3. Provision Agent Gateways, IAP, and Model Armor (KOREA_RRN/SSN) with Terraform

Next, use Terraform to provision the three Cloud Run MCP servers, three Agent Gateways, IAP (`DRY_RUN` mode), Model Armor and Cloud DLP templates, the Vertex AI Agent Engine shell, and the observability dashboard.

### 1. Inspect the Terraform Governance Configuration

Before deploying, inspect `terraform/variables.tf` to see how each security layer is configured:

```bash
cat ~/agent-gateway-governance/terraform/variables.tf
```

Key configuration highlights include:

1. **`model_armor_pii_types`**: Defaults to `["US_SOCIAL_SECURITY_NUMBER", "KOREA_RRN"]`, enabling Cloud DLP to detect both US Social Security Numbers (`323-45-6789`) and Korean Resident Registration Numbers (`850315-1234566`, `870822-2345673`) and redact them as `[US_SOCIAL_SECURITY_NUMBER]` and `[KOREA_RRN]`.
2. **`enforcement_mode = "DRY_RUN"`**: Deploys the IAP CEL policy (`request.mcp.tool.name != "send_email"`) in front of `corporate-email` in `DRY_RUN` mode initially. During the first test, `send_email` calls are logged as audit findings without being blocked.
3. **`enable_private_networking`**: Defaults to `false` (public `*.run.app` ingress + IAM authentication) for rapid lab execution, and can be set to `true` in isolated enterprise networks to provision a custom VPC, Proxy-Only Subnet, Network Attachment, and Private Cloud DNS.

### 2. Create `terraform.tfvars` and Provision All Infrastructure

Run the following commands to generate `terraform.tfvars` and execute `terraform apply`:

```bash
cd ~/agent-gateway-governance/terraform

cat <<EOF > terraform.tfvars
project_id                = "${PROJECT_ID}"
region                    = "${REGION}"
enable_private_networking = false
enforcement_mode          = "DRY_RUN"
EOF

terraform apply -auto-approve
```

> **Note**: Provisioning the Cloud DLP templates, Model Armor template, three Cloud Run services, three Agent Gateways, and IAP bindings takes approximately 2 to 3 minutes.

### 3. Verify Terraform Outputs

Once provisioning finishes, inspect the generated Agent Gateway endpoint URLs and Agent Engine resource name:

```bash
terraform output
```

Example output:

```text
agent_engine_resource_name = "projects/123456789012/locations/us-central1/reasoningEngines/9876543210987654321"
agent_gateway_endpoints = {
  "corporate-email" = "https://agw-corporate-email-xxxxx.us-central1.agentgateway.cloud.goog/mcp"
  "income-verification" = "https://agw-income-verification-xxxxx.us-central1.agentgateway.cloud.goog/mcp"
  "legacy-dms" = "https://agw-legacy-dms-xxxxx.us-central1.agentgateway.cloud.goog/mcp"
}
```

<ql-activity-tracking step=2>
Check Agent Gateways, IAP, and Model Armor Provisioning
</ql-activity-tracking>

---

## Task 4. Deploy the Mortgage Underwriting Agent (`mortgage-agent`) and Grant Egress IAM Roles

Terraform pre-created an empty Vertex AI Agent Engine (Reasoning Engine) shell so that its dedicated Agent Identity is issued ahead of time. Now you will upload the ADK `mortgage-agent` Python code to that Agent Engine resource and grant least-privilege IAM permissions so the agent can traverse the Agent Gateways.

### 1. Inspect the ADK Agent's Agent Gateway Authentication Code

Check how the agent connects to the three Agent Gateway endpoints in `src/mortgage-agent/agent/agent.py`:

```bash
sed -n '90,155p' ~/agent-gateway-governance/src/mortgage-agent/agent/agent.py
```

* Rather than calling backend Cloud Run URLs directly, the agent communicates exclusively through the three **Agent Gateway URLs (`*.agentgateway.cloud.goog/mcp`)** injected via `AGENT_GATEWAY_ENDPOINTS`.
* The `GoogleCredentialsAuth` class automatically mints OAuth2 access tokens and Google ID tokens for the Agent Identity at runtime and injects them into the HTTP `Authorization: Bearer ...` header.

### 2. Deploy the `mortgage-agent` Code to Vertex AI Agent Engine

Use `uv` to run `deploy_agent.py`, which reads the Terraform outputs and updates the existing Agent Engine resource with the agent code and system instructions:

```bash
cd ~/agent-gateway-governance/src/mortgage-agent
uv run deploy_agent.py
```

When the deployment completes, you will see `Update completed: projects/.../locations/us-central1/reasoningEngines/...`.

### 3. Grant Agent Egress IAM Roles (`grant_agent_mcp_egress.sh`)

To traverse the Agent Gateway data plane and invoke the server-side Cloud Run service (`corporate-email`), the Agent Identity requires two IAM roles:

1. **`roles/networkservices.agentGatewayUser`**: Allows the agent to send traffic through the Agent Gateways in the project.
2. **`roles/run.invoker`**: Allows the server-side Agent Gateway (`corporate-email`) to invoke the backing Cloud Run service on behalf of the verified Agent Identity.

Run the helper script to bind these permissions:

```bash
cd ~/agent-gateway-governance
chmod +x ./scripts/grant_agent_mcp_egress.sh
./scripts/grant_agent_mcp_egress.sh
```

> **Note**: IAM policy bindings can take roughly 60 seconds to propagate globally across Google Cloud.

<ql-activity-tracking step=3>
Check Vertex AI Agent Engine Deployment and Egress IAM Roles
</ql-activity-tracking>

---

## Task 5. Phase 1 Verification: Test IAP `DRY_RUN` Mode and Model Armor PII Redaction

Now open the **Agent Engine Playground** in the Google Cloud Console and run the mortgage underwriting scenario to verify two behaviors simultaneously:

1. **Model Armor + Cloud DLP (`CONTENT_AUTHZ`)**: Verify that Korean Resident Registration Numbers (`850315-1234566`, `870822-2345673`) and US SSNs (`323-45-6789`, `321-54-9876`) returned by `legacy-dms` and `income-verification` are redacted into `[KOREA_RRN]` and `[US_SOCIAL_SECURITY_NUMBER]`.
2. **IAP (`REQUEST_AUTHZ` - `DRY_RUN` Mode)**: Verify that the `send_email` tool on `corporate-email` is permitted to execute while the policy is in `DRY_RUN` mode.

![Comparison of DRY_RUN vs. ENFORCED Mode and Observability Dashboard](img/03-dryrun-vs-enforced-flow.png)

### 1. Open the Vertex AI Agent Engine Playground

1. In the Google Cloud Console top search bar, type **Agent Engine** and navigate to **Vertex AI > Agent Engine**.
2. Confirm that the region is set to **`us-central1`**, then click the deployed **`mortgage_agent`**.
3. Click the **Playground** tab at the top.

### 2. Run the Mortgage Underwriting and Email Prompt

Enter the following prompt in the Playground chat input and send it:

```text
Please evaluate whether co-applicants Minjun Kim and Seoyeon Lee qualify for a new 2026 residential mortgage:
1) Search their tax returns and document metadata in legacy-dms to verify their Korean RRN, US SSN, and reported income,
2) Verify both applicants' income and 2026 DTI ratio using income-verification,
3) Search and read the latest 2026 underwriting DTI limit guideline email in corporate-email, and
4) Send an email (send_email) summarizing the underwriting decision to underwriting-team@apex-financial.kr.
```

### 3. Verify the Agent Response

Confirm that the agent invokes the tools across all three MCP servers and returns the following results:

* **PII Redaction Verified (Model Armor + Cloud DLP Active)**:
  * Minjun Kim's Korean RRN (`850315-1234566`) and Seoyeon Lee's Korean RRN (`870822-2345673`) are masked as **`[KOREA_RRN]`**.
  * Their US SSNs (`323-45-6789`, `321-54-9876`) are masked as **`[US_SOCIAL_SECURITY_NUMBER]`**, ensuring raw identifiers never enter the LLM context or chat output.
* **2026 DTI Assessment & Outbound Email Verified (IAP `DRY_RUN` Mode)**:
  * Compared against the 2026 maximum DTI cap (**45.0%**) specified in internal email `msg-002`, the applicants' combined estimated DTI (**28.4%** on $237,000 combined annual income) qualifies as **Eligible**.
  * Because the IAP policy is currently in `DRY_RUN` mode, the `send_email` tool call succeeds (`status: sent`).

---

## Task 6. Analyze the Unified Observability Dashboard, Cloud Trace, and Cloud Logging

Agent Gateway automatically emits standardized metrics, distributed traces (Cloud Trace), and security audit logs (Cloud Logging) for all MCP traffic passing through it.

### 1. View the Cloud Monitoring Governance Dashboard

1. In the Google Cloud Console, navigate to **Monitoring > Dashboards**.
2. Click the **`Agent Gateway Governance Overview`** dashboard created by Terraform.

![Agent Gateway Governance Overview Dashboard](img/05-observability-dashboard.png)

The dashboard displays four key governance panels:

* **MCP Request Rate by Tool**: Per-second invocation rate broken down by tool (`search_tax_returns`, `get_document_metadata`, `verify_income`, `search_emails`, `read_email`, `send_email`).
* **Agent Gateway Latency (p50 / p95)**: Processing latency across the gateway and Service Extensions (IAP, Model Armor).
* **Model Armor Verdict Breakdown**: Ratio of requests where PII detection and redaction occurred during the `CONTENT_AUTHZ` phase.
* **Active MCP Sessions**: Number of active agent-to-gateway MCP sessions.

### 2. Query Agent Gateway and Model Armor Logs in Cloud Logging

Run the following command in Cloud Shell to inspect MCP request logs and security extension audit entries:

```bash
gcloud logging read \
  'resource.type="networkservices.googleapis.com/AgentGateway" OR protoPayload.serviceName="iap.googleapis.com" OR protoPayload.serviceName="modelarmor.googleapis.com"' \
  --project="${PROJECT_ID}" \
  --limit=10 \
  --format="table(timestamp, resource.type, httpRequest.status, jsonPayload.mcpMethod, jsonPayload.mcpToolName)"
```

---

## Task 7. Phase 2 Verification: Switch IAP to `ENFORCED` Mode and Verify Real-Time `send_email` Blocking

Having verified in `DRY_RUN` mode that read-only tools (`search_emails`, `read_email`) are permitted while `send_email` is flagged as a policy violation, you will now switch the IAP policy on `agw-corporate-email` to **`ENFORCED` mode (`enforcement_mode = null`)** to block unauthorized outbound email calls in real time.

### 1. Review the IAP CEL Policy Expression

Inspect the CEL expression defined for `agw-corporate-email` in `terraform/main.tf`:

```hcl
expression = <<-EOT
  request.mcp.method in ["initialize", "notifications/initialized", "tools/list", "ResourceList", "PromptList"] ||
  (request.mcp.method == "tools/call" && request.mcp.tool.name != "send_email")
EOT
```

* Allows MCP session initialization (`initialize`) and tool discovery (`tools/list`).
* For tool invocations (`tools/call`), permits only tools whose name is not `send_email` (`search_emails`, `read_email`), immediately rejecting `send_email` calls with `403 Permission Denied`.

### 2. Apply `enforcement_mode = null` (Enforced Mode) with Terraform

In Cloud Shell, update `enforcement_mode` to `null` in `terraform.tfvars` and run `terraform apply`:

```bash
cd ~/agent-gateway-governance/terraform

cat <<EOF > terraform.tfvars
project_id                = "${PROJECT_ID}"
region                    = "${REGION}"
enable_private_networking = false
enforcement_mode          = null
EOF

terraform apply -auto-approve
```

> **Note**: It takes approximately 60 to 90 seconds for the updated IAP policy to propagate to the Agent Gateway data plane.

### 3. Verify Real-Time `send_email` Blocking in the Playground

After waiting 60 seconds, return to **Vertex AI > Agent Engine > `mortgage_agent` > Playground**, start a new session, and submit the prompt again:

```text
Please re-evaluate whether co-applicants Minjun Kim and Seoyeon Lee qualify for the 2026 residential mortgage, and send the underwriting summary via email (send_email) to underwriting-team@apex-financial.kr.
```

Observe the enforced governance behavior:

1. **Read Lookups & PII Redaction Succeed**: Calls to `legacy-dms` (`search_tax_returns`), `income-verification` (`verify_income`), and `corporate-email` (`search_emails`, `read_email`) succeed, and Korean RRNs (`[KOREA_RRN]`) and US SSNs (`[US_SOCIAL_SECURITY_NUMBER]`) remain redacted.
2. **`send_email` Call Blocked Immediately**: As soon as the agent attempts to invoke `send_email`, **IAP (`REQUEST_AUTHZ`) on `agw-corporate-email` rejects the request with `403 Forbidden / Permission Denied`**.
3. **Graceful Agent Degradation**: The agent presents the complete underwriting summary in the chat response while noting that the outbound email could not be sent because `send_email` was denied by security policy.

<ql-activity-tracking step=4>
Check IAP Enforced Mode Switch and send_email Blocking
</ql-activity-tracking>

---

## Congratulations!

You have built and verified an end-to-end enterprise agent governance architecture for Apex Financial Group combining **Agent Gateway**, **Identity-Aware Proxy (IAP CEL)**, **Model Armor + Cloud DLP (`KOREA_RRN` / `US_SOCIAL_SECURITY_NUMBER` redaction)**, and **Cloud Monitoring / Trace observability**!

### Key Takeaways

* **Unified Client-Side (`agent-egress`) & Server-Side (`cloud-run`) Control**: Protected both external/legacy APIs and internal Cloud Run MCP servers with Agent Gateway without modifying application code.
* **Data Loss Prevention (`CONTENT_AUTHZ`)**: Linked Model Armor and Cloud DLP to automatically redact Korean Resident Registration Numbers (`[KOREA_RRN]`) and US SSNs (`[US_SOCIAL_SECURITY_NUMBER]`) in MCP `structuredContent` payloads before they reach the LLM context.
* **Context-Aware Tool Authorization (`REQUEST_AUTHZ`)**: Used IAP CEL expressions and the `DRY_RUN` ➔ `ENFORCED` lifecycle to allow safe read tools (`search_emails`, `read_email`) while blocking high-risk write tools (`send_email`).
