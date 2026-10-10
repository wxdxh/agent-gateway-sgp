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
if ! command -v uv &>/dev/null; then
  curl -LsSf https://astral.sh/uv/install.sh | sh
  export PATH="${HOME}/.local/bin:${PATH}"
fi
if ! command -v agents-cli &>/dev/null; then
  uv tool install google-agents-cli
  export PATH="${HOME}/.local/bin:${PATH}"
fi

cd "${SCRIPT_DIR}/conversational-banking"
rm -f deployment_metadata.json
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

echo "==> Step 5: Granting Agent Registry & Cloud Run permissions to Agent Identity..."
TOKEN="$(gcloud auth print-access-token)"
EFFECTIVE_ID="$(curl -fsS -H "Authorization: Bearer ${TOKEN}" \
  "https://${LOCATION}-aiplatform.googleapis.com/v1beta1/projects/${PROJECT_ID}/locations/${LOCATION}/reasoningEngines" | \
  python3 -c 'import sys, json; engines=json.load(sys.stdin).get("reasoningEngines", []); matches=[e for e in engines if e.get("displayName")=="conversational-banking"]; print(matches[0].get("spec", {}).get("effectiveIdentity", "") if matches else "")' 2>/dev/null || true)"

if [[ -n "${EFFECTIVE_ID}" ]]; then
  AGENT_PRINCIPAL="principal://${EFFECTIVE_ID}"
  echo "Detected Agent Identity: ${AGENT_PRINCIPAL}"
  for ROLE in "roles/agentregistry.viewer" "roles/agentregistry.user" "roles/aiplatform.user"; do
    gcloud projects add-iam-policy-binding "${PROJECT_ID}" \
      --member="${AGENT_PRINCIPAL}" \
      --role="${ROLE}" \
      --condition=None \
      --quiet >/dev/null || true
  done
  gcloud run services add-iam-policy-binding banking-mcp-server \
    --region="${LOCATION}" \
    --member="${AGENT_PRINCIPAL}" \
    --role="roles/run.servicesInvoker" \
    --project="${PROJECT_ID}" \
    --quiet >/dev/null || true
fi

RE_SA="serviceAccount:service-${PROJECT_NUM}@gcp-sa-aiplatform-re.iam.gserviceaccount.com"
for ROLE in "roles/agentregistry.viewer" "roles/aiplatform.user"; do
  gcloud projects add-iam-policy-binding "${PROJECT_ID}" \
    --member="${RE_SA}" \
    --role="${ROLE}" \
    --condition=None \
    --quiet >/dev/null 2>&1 || true
done
gcloud run services add-iam-policy-binding banking-mcp-server \
  --region="${LOCATION}" \
  --member="${RE_SA}" \
  --role="roles/run.servicesInvoker" \
  --project="${PROJECT_ID}" \
  --quiet >/dev/null 2>&1 || true

for ep_id in $(gcloud alpha agent-registry endpoints list --project="${PROJECT_ID}" --location="${LOCATION}" --format="value(name.basename())" 2>/dev/null || true); do
  gcloud alpha iap web add-iam-policy-binding \
    --resource-type=agent-registry \
    --endpoint="${ep_id}" \
    --region="${LOCATION}" \
    --project="${PROJECT_ID}" \
    --member="${RE_SA}" \
    --role="roles/iap.egressor" \
    --quiet >/dev/null 2>&1 || true
done

echo "================================================================================"
echo " Gemini Enterprise Agent Runtime deployment initiated in the background."
echo " Proceed to Step 6 (06-setup-sgp-networking.sh) and Step 7 (07-create-sgp-policy.sh)."
echo "================================================================================"
echo "==> Step 5 completed successfully."
