# Enterprise AI Agent Governance with Agent Gateway and Semantic Governance Policies (SGP)

This project provides the complete source code, infrastructure automation, and test suite for the Google Cloud Codelab:
**[Governing Autonomous AI Agents with Agent Gateway and Semantic Governance Policies](https://codelabs.developers.google.com/enterprise-agent-governance-sgp)**.

---

## 🏗️ Architecture Overview

Autonomous AI agents powered by LLMs can make decisions and trigger actions against real-world backend APIs. Directly connecting agents to critical financial systems introduces security and financial risks. 

This solution establishes a **zero-trust governance layer**:

```
[User Prompt]
      │
      ▼
[Vertex AI Agent Runtime] (Conversational Banking ADK Agent)
      │
      ▼ (All outbound tool calls intercepted)
[Google Cloud Agent Gateway] (agent-egress, AGENT_TO_ANYWHERE)
      │
      ├──▶ [Private Service Connect (policy.internal)]
      │         │
      │         ▼
      │    [Semantic Governance Policy (SGP) Engine]
      │    - Evaluates natural language constraints with LLM-as-judge
      │    - Verdict: ALLOW or DENY (with explanatory rationale)
      │
      ▼ (Only if ALLOW)
[Cloud Run: Banking MCP Server] (/mcp JSON-RPC endpoint)
      - get_account
      - lookup_customer_by_phone
      - transfer_to_phone
      - pay_bill
```

---

## 📁 Repository Structure

```
agentgateway/
├── banking-mcp-server/             # Production Model Context Protocol (MCP) Server
│   ├── server.py                   # FastMCP / FastAPI JSON-RPC 2.0 & /tools endpoints
│   ├── Dockerfile                  # Cloud Run container definition
│   ├── requirements.txt            # Dependencies (fastapi, uvicorn, pydantic, mcp)
│   └── test_server.py              # Automated unit tests for tools & JSON-RPC
│
├── conversational-banking/         # ADK Banking Agent for Vertex AI
│   ├── app/
│   │   ├── agent.py                # Agent definition with AgentRegistry MCP toolset
│   │   └── fast_api_app.py         # Local/Runtime FastAPI wrapper
│   ├── Dockerfile                  # Agent Gateway CA-ready container
│   ├── pyproject.toml              # Dependencies (google-adk[agent-identity,mcp], etc.)
│   └── agents-cli-manifest.yaml    # Agents CLI project descriptor
│
├── env.sh                          # Central configuration & project variables
├── 01-setup-env.sh                 # APIs, Service Identity & IAM setup
├── 02-setup-networking.sh          # Proxy subnet, Network Attachment, PSC, DNS
├── 03-setup-agent-gateway.sh       # Agent Gateway & Authz Policy deployment
├── 04-deploy-mcp.sh                # Cloud Run deployment & invoker permission
├── 05-register-mcp.sh              # Agent Registry registration & endpoint allowlisting
├── 06-deploy-agent.sh              # Vertex AI Agent Runtime deployment
├── 07-create-sgp-policy.sh         # Natural language SGP rule creation
├── 08-test.sh                      # Testing guide & Cloud Logging verification
├── 99-cleanup.sh                   # Complete teardown of cloud resources
└── deploy-all.sh                   # Orchestrated end-to-end deployment script
```

---

## 🛠️ What Was Built (Bridging Missing Codelab Assets)

1. **`banking-mcp-server`**:
   The original Codelab assumed a pre-existing `banking-mcp-server` directory. We created a full Python implementation supporting:
   - **Tool Discovery (`GET /tools`)**: Returns the exact JSON tool specification required by `curl -s "${MCP_URL}/tools" | python3 -c ...` to create `toolspec.json`.
   - **MCP JSON-RPC 2.0 (`POST /mcp`)**: Complies with the Model Context Protocol specification for `initialize`, `tools/list`, `tools/call`, and `ping`.
   - **Mock Banking Core**: Pre-seeded accounts for testing:
     - `CUST005` (Alice Smith): $10,000.00 (Phone: `555-0005`)
     - `CUST001` (Bob Jones): $3,500.00 (Phone: `555-0001`)
     - `CUST002` (Charlie Brown): $1,200.00 (Phone: `555-0002`)
   - **4 Supported Operations**:
     - `get_account(customer_id)`
     - `lookup_customer_by_phone(phone)`
     - `transfer_to_phone(customer_id, target_phone, amount)`
     - `pay_bill(customer_id, biller_name, account_number, amount)`

2. **ADK Agent Dependencies & Configuration**:
   - Resolved required ADK extras: `google-adk[agent-identity,mcp]` required for `AgentRegistry.get_mcp_toolset(...)`.
   - Dynamic environment configuration fallback for local and Cloud Run/Vertex AI runtime.

3. **Modular Deployment Pipeline**:
   - Automated scripts `01` through `08` plus `deploy-all.sh` and `99-cleanup.sh`.

---

## 🧪 Local Verification

Before deploying to Google Cloud, you can verify the Banking MCP server logic locally:

```bash
cd banking-mcp-server
python3 test_server.py
```

Expected output:
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

## 🚀 Step-by-Step Google Cloud Deployment

### Prerequisites
- Active Google Cloud project with billing enabled.
- `gcloud` authenticated (`gcloud auth login` and `gcloud auth application-default login`).
- `agents-cli` installed (`uv tool install google-agents-cli` or `pip install google-agents-cli`).

### Option A: One-Click Deployment
```bash
./deploy-all.sh
```

### Option B: Step-by-Step Manual Execution

```bash
# 1. Configure environment & IAM
./01-setup-env.sh

# 2. Setup VPC Networking, PSC Endpoint, and Cloud DNS
./02-setup-networking.sh

# 3. Create Agent Gateway (agent-egress) and attach Authz Policy
./03-setup-agent-gateway.sh

# 4. Deploy Banking MCP Server to Cloud Run
./04-deploy-mcp.sh

# 5. Register MCP Server and Google APIs in Agent Registry
./05-register-mcp.sh

# 6. Deploy Conversational Banking Agent to Vertex AI Agent Runtime
./06-deploy-agent.sh

# 7. Create Semantic Governance Policy (Block transfers > $1,000 USD)
./07-create-sgp-policy.sh
```

---

## 🔍 Validation in Vertex AI Playground

1. In Google Cloud Console, navigate to **Vertex AI** > **Reasoning Engines** (or Agent Engine).
2. Open **conversational-banking** and click the **Playground** tab.

### Turn 1: Authenticate
- **Prompt**: `I am customer CUST005`
- **Behavior**: The agent calls `get_account(customer_id="CUST005")`, welcomes Alice Smith, and displays her balance of $10,000.00.

### Turn 2: Allowed Transaction (< $1,000 limit)
- **Prompt**: `transfer 50 to 555-0001`
- **Behavior**:
  1. The agent calls `transfer_to_phone(customer_id="CUST005", target_phone="555-0001", amount=50)`.
  2. Agent Gateway routes request to SGP engine over PSC.
  3. SGP evaluates constraint: $50 <= $1000 -> **ALLOW**.
  4. The MCP server executes transfer. Alice's balance becomes $9,950.00.

### Turn 3: Blocked Transaction (> $1,000 limit)
- **Prompt**: `transfer 2000 to 555-0002`
- (If agent asks for confirmation, reply `y`)
- **Behavior**:
  1. The agent calls `transfer_to_phone(customer_id="CUST005", target_phone="555-0002", amount=2000)`.
  2. Agent Gateway routes request to SGP engine over PSC.
  3. SGP evaluates constraint: "Block any transfer value exceeding USD 1000."
  4. SGP issues verdict: **DENY** with rationale.
  5. The tool call is terminated at the Gateway. The MCP server is never reached.
  6. Agent receives the denial and politely informs the user:
     `"This action is disallowed because the transfer amount of $2000.00 exceeds the high-value transfer limit of $1000.00."`

---

## 📜 Audit Logs in Cloud Logging

Every policy evaluation is logged with the LLM-as-judge rationale:

```bash
gcloud logging read 'logName="projects/'"${PROJECT_ID}"'/logs/semantic-governance-policy"' --limit=5 --format=json
```

Example audit payload:
```json
{
  "actionName": "transfer_to_phone",
  "toolName": "transfer_to_phone",
  "verdict": "DENY",
  "rationale": "This action is disallowed because the transfer amount of $2000.00 exceeds the high-value transfer limit of $1000.00."
}
```

---

## 🧹 Cleanup

To prevent unnecessary costs when you are finished testing:

```bash
./99-cleanup.sh
```
