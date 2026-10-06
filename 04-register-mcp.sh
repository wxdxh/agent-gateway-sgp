#!/usr/bin/env bash
set -eo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/env.sh"
[[ -f "${SCRIPT_DIR}/.env.runtime" ]] && source "${SCRIPT_DIR}/.env.runtime"

if [[ -z "${MCP_URL}" ]]; then
  export MCP_URL="$(gcloud run services describe banking-mcp-server \
    --region="${LOCATION}" \
    --project="${PROJECT_ID}" \
    --format="value(status.url)" 2>/dev/null || true)"
fi

if [[ -z "${MCP_URL}" ]]; then
  echo "Error: MCP_URL is not set. Run 03-deploy-mcp.sh first."
  exit 1
fi

echo "==> Step 4: Extracting tool specification from MCP server..."
ID_TOKEN="$(gcloud auth print-identity-token 2>/dev/null || true)"
if [ -n "${ID_TOKEN}" ]; then
  curl -fsS -H "Authorization: Bearer ${ID_TOKEN}" "${MCP_URL}/tools" | python3 -c 'import sys, json; tools=json.load(sys.stdin); json.dump({"tools": tools}, open("'${SCRIPT_DIR}'/toolspec.json", "w"))'
else
  curl -fsS "${MCP_URL}/tools" | python3 -c 'import sys, json; tools=json.load(sys.stdin); json.dump({"tools": tools}, open("'${SCRIPT_DIR}'/toolspec.json", "w"))'
fi

echo "==> Step 4: Registering MCP service in Agent Registry..."
gcloud alpha agent-registry services create banking-mcp-server \
  --project="${PROJECT_ID}" \
  --location="${LOCATION}" \
  --display-name="Banking MCP Server" \
  --interfaces=url="${MCP_URL}/mcp",protocolBinding=JSONRPC \
  --mcp-server-spec-type=tool-spec \
  --mcp-server-spec-content="${SCRIPT_DIR}/toolspec.json" || true

echo "==> Step 4: Retrieving MCP Server Resource ID..."
export MCP_SERVER_NAME="$(gcloud alpha agent-registry mcp-servers list \
  --project="${PROJECT_ID}" \
  --location="${LOCATION}" \
  --filter="displayName:'Banking MCP Server'" \
  --format="value(name.basename())" | head -n 1)"

if [[ -z "${MCP_SERVER_NAME}" ]]; then
  echo "Warning: Could not automatically find MCP_SERVER_NAME. Listing all mcp-servers:"
  gcloud alpha agent-registry mcp-servers list --project="${PROJECT_ID}" --location="${LOCATION}"
else
  echo "=================================================="
  echo " Registered MCP Server ID: ${MCP_SERVER_NAME}"
  echo "=================================================="
  echo "export MCP_SERVER_NAME=\"${MCP_SERVER_NAME}\"" >> "${SCRIPT_DIR}/.env.runtime"
fi

echo "==> Step 4: Allowlisting Google Cloud system endpoints for Agent Gateway..."
ENDPOINTS=(
  "Gemini Enterprise Global API | https://aiplatform.googleapis.com"
  "Cloud Trace API | https://telemetry.googleapis.com"
  "Cloud Logging API | https://logging.googleapis.com"
  "Agent Registry API | https://agentregistry.googleapis.com"
)

for entry in "${ENDPOINTS[@]}"; do
  IFS="|" read -r name url <<< "$entry"
  name="$(echo "$name" | xargs)"
  url="$(echo "$url" | xargs)"
  service_id="$(echo "$name" | tr '[:upper:]' '[:lower:]' | tr -cd 'a-z0-9' | cut -c 1-40)"

  echo "Registering endpoint '${name}' (${url})..."
  res="$(gcloud alpha agent-registry services create "${service_id}" \
    --project="${PROJECT_ID}" \
    --location="${LOCATION}" \
    --display-name="${name}" \
    --endpoint-spec-type=no-spec \
    --interfaces=url="${url}",protocolBinding=JSONRPC \
    --format="value(registryResource)" 2>&1)" || true

  ep_id="$(echo "${res}" | grep -oE 'agentregistry-[0-9a-f-]+$' | head -n 1 || true)"
  if [[ -n "${ep_id}" ]]; then
    echo "Binding roles/iap.egressor on endpoint ${ep_id}..."
    gcloud alpha iap web add-iam-policy-binding \
      --resource-type=agent-registry \
      --endpoint="${ep_id}" \
      --region="${LOCATION}" \
      --project="${PROJECT_ID}" \
      --member="${AGW_SA}" \
      --role="roles/iap.egressor" \
      --quiet >/dev/null || true
    gcloud alpha iap web add-iam-policy-binding \
      --resource-type=agent-registry \
      --endpoint="${ep_id}" \
      --region="${LOCATION}" \
      --project="${PROJECT_ID}" \
      --member="serviceAccount:service-${PROJECT_NUM}@gcp-sa-aiplatform-re.iam.gserviceaccount.com" \
      --role="roles/iap.egressor" \
      --quiet >/dev/null || true
  fi
done

echo "==> Step 4 completed successfully."
