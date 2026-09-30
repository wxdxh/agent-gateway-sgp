#!/usr/bin/env bash
set -eo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/env.sh"
[[ -f "${SCRIPT_DIR}/.env.runtime" ]] && source "${SCRIPT_DIR}/.env.runtime"

if [[ -z "${AGENT_ID}" ]]; then
  export AGENT_ID="$(gcloud alpha agent-registry agents list \
    --project="${PROJECT_ID}" \
    --location="${LOCATION}" \
    --filter="displayName:'conversational-banking'" \
    --format="value(name.basename())" 2>/dev/null | head -n 1 || true)"
fi

if [[ -z "${MCP_SERVER_NAME}" ]]; then
  export MCP_SERVER_NAME="$(gcloud alpha agent-registry mcp-servers list \
    --project="${PROJECT_ID}" \
    --location="${LOCATION}" \
    --filter="displayName:'Banking MCP Server'" \
    --format="value(name.basename())" 2>/dev/null | head -n 1 || true)"
fi

# In ADK, MCP tools registered from "Banking MCP Server" are exposed with prefix Banking_MCP_Server_
TOOL_NAME="Banking_MCP_Server_transfer_to_phone"

echo "Creating or Updating Semantic Governance Policy 'high-value-limit'..."
echo "  Agent:      projects/${PROJECT_ID}/locations/${LOCATION}/agents/${AGENT_ID}"
echo "  MCP Server: projects/${PROJECT_ID}/locations/${LOCATION}/mcpServers/${MCP_SERVER_NAME}"
echo "  Tool:       ${TOOL_NAME}"
echo "  Constraint: Block any transfer value exceeding USD 1000."

if gcloud beta ai semantic-governance-policies describe high-value-limit --location="${LOCATION}" &>/dev/null; then
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
