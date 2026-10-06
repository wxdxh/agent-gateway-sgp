#!/usr/bin/env bash
set -eo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/env.sh"
[[ -f "${SCRIPT_DIR}/.env.runtime" ]] && source "${SCRIPT_DIR}/.env.runtime"

if [[ -z "${MCP_SERVER_NAME}" ]]; then
  export MCP_SERVER_NAME="$(gcloud alpha agent-registry mcp-servers list \
    --project="${PROJECT_ID}" \
    --location="${LOCATION}" \
    --filter="displayName:'Banking MCP Server'" \
    --format="value(name.basename())" 2>/dev/null | head -n 1 || true)"
fi

if [[ -z "${MCP_SERVER_NAME}" ]]; then
  echo "Error: MCP_SERVER_NAME is not set. Run 04-register-mcp.sh first."
  exit 1
fi

echo "==> Step 5: Extracting Agent Gateway TLS Inspection Root CA certificate..."
gcloud network-services agent-gateways describe agent-egress \
  --location="${LOCATION}" \
  --project="${PROJECT_ID}" \
  --format="value(agentGatewayCard.rootCertificates[0])" > "${SCRIPT_DIR}/conversational-banking/agent-gateway-ca.crt"

echo "==> Step 5: Deploying Conversational Banking Agent to Gemini Enterprise Agent Runtime..."
cd "${SCRIPT_DIR}/conversational-banking"
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

echo "================================================================================"
echo " Gemini Enterprise Agent Runtime deployment initiated in the background."
echo " Proceed to Step 6 (06-setup-sgp-networking.sh) and Step 7 (07-create-sgp-policy.sh)."
echo "================================================================================"
echo "==> Step 5 completed successfully."
