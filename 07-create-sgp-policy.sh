#!/usr/bin/env bash
set -eo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/env.sh"
[[ -f "${SCRIPT_DIR}/.env.runtime" ]] && source "${SCRIPT_DIR}/.env.runtime"

echo "==> Step 7: Registering SGP Authorization Extension (sgp-authzextension)..."
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

echo "==> Step 7: Generating Content Authorization Policy definition (agent-egress-sgp-authzpolicy)..."
cat > "${SCRIPT_DIR}/agent-egress-sgp-authzpolicy.yaml" << YAML_EOF
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
YAML_EOF

echo "==> Step 7: Importing Content Authorization Policy..."
gcloud beta network-security authz-policies import agent-egress-sgp-authzpolicy \
  --source="${SCRIPT_DIR}/agent-egress-sgp-authzpolicy.yaml" \
  --location="${LOCATION}" \
  --project="${PROJECT_ID}"

if [[ -z "${MCP_SERVER_NAME}" ]]; then
  export MCP_SERVER_NAME="$(gcloud alpha agent-registry mcp-servers list \
    --project="${PROJECT_ID}" \
    --location="${LOCATION}" \
    --filter="displayName:'Banking MCP Server'" \
    --format="value(name.basename())" 2>/dev/null | head -n 1 || true)"
fi

echo "==> Step 7: Checking if Conversational Banking Agent is registered in Agent Registry..."
if [[ -z "${AGENT_ID}" ]]; then
  export AGENT_ID="$(gcloud alpha agent-registry agents list \
    --project="${PROJECT_ID}" \
    --location="${LOCATION}" \
    --filter="displayName:'conversational-banking'" \
    --format="value(name.basename())" 2>/dev/null | head -n 1 || true)"
fi

while [[ -z "${AGENT_ID}" ]]; do
  echo "Waiting for background Agent Runtime deployment (started in Step 5) to finish registering in Agent Registry... (checking again in 20s)"
  sleep 20
  export AGENT_ID="$(gcloud alpha agent-registry agents list \
    --project="${PROJECT_ID}" \
    --location="${LOCATION}" \
    --filter="displayName:'conversational-banking'" \
    --format="value(name.basename())" 2>/dev/null | head -n 1 || true)"
done

echo "=================================================="
echo " Registered Agent ID: ${AGENT_ID}"
echo "=================================================="
if ! grep -q "AGENT_ID=\"${AGENT_ID}\"" "${SCRIPT_DIR}/.env.runtime" 2>/dev/null; then
  echo "export AGENT_ID=\"${AGENT_ID}\"" >> "${SCRIPT_DIR}/.env.runtime"
fi

# In ADK, MCP tools registered from "Banking MCP Server" are exposed with prefix Banking_MCP_Server_
TOOL_NAME="Banking_MCP_Server_transfer_to_phone"

echo "==> Step 7: Creating or Updating Semantic Governance Policy 'high-value-limit'..."
echo "  Agent:      projects/${PROJECT_ID}/locations/${LOCATION}/agents/${AGENT_ID}"
echo "  MCP Server: projects/${PROJECT_ID}/locations/${LOCATION}/mcpServers/${MCP_SERVER_NAME}"
echo "  Tool:       ${TOOL_NAME}"
echo "  Constraint: Block any transfer value exceeding USD 1000."

if gcloud beta ai semantic-governance-policies describe high-value-limit --location="${LOCATION}" --project="${PROJECT_ID}" &>/dev/null; then
  echo "Policy high-value-limit already exists. Updating..."
  gcloud beta ai semantic-governance-policies update high-value-limit \
    --project="${PROJECT_ID}" \
    --location="${LOCATION}" \
    --agent="projects/${PROJECT_ID}/locations/${LOCATION}/agents/${AGENT_ID}" \
    --mcp-tools="mcp-server=projects/${PROJECT_ID}/locations/${LOCATION}/mcpServers/${MCP_SERVER_NAME},tools=${TOOL_NAME}" \
    --natural-language-constraint="Block any transfer value exceeding USD 1000."
else
  gcloud beta ai semantic-governance-policies create high-value-limit \
    --project="${PROJECT_ID}" \
    --location="${LOCATION}" \
    --display-name="High Value Transfer Limit" \
    --agent="projects/${PROJECT_ID}/locations/${LOCATION}/agents/${AGENT_ID}" \
    --mcp-tools="mcp-server=projects/${PROJECT_ID}/locations/${LOCATION}/mcpServers/${MCP_SERVER_NAME},tools=${TOOL_NAME}" \
    --natural-language-constraint="Block any transfer value exceeding USD 1000."
fi

echo "==> Step 7 completed successfully."
