#!/usr/bin/env bash
set -eo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/env.sh"

echo "==> Step 4: Deploying banking-mcp-server to Cloud Run..."
cd "${SCRIPT_DIR}/banking-mcp-server"

gcloud run deploy banking-mcp-server \
  --source=. \
  --region="${LOCATION}" \
  --project="${PROJECT_ID}" \
  --allow-unauthenticated \
  --quiet

export MCP_URL="$(gcloud run services describe banking-mcp-server \
  --region="${LOCATION}" \
  --project="${PROJECT_ID}" \
  --format="value(status.url)")"

echo "=================================================="
echo " Banking MCP Server URL: ${MCP_URL}"
echo "=================================================="
echo "export MCP_URL=\"${MCP_URL}\"" >> "${SCRIPT_DIR}/.env.runtime"

echo "==> Step 4: Verifying /tools endpoint..."
ID_TOKEN="$(gcloud auth print-identity-token 2>/dev/null || true)"
if [ -n "${ID_TOKEN}" ]; then
  curl -fsS -H "Authorization: Bearer ${ID_TOKEN}" "${MCP_URL}/tools" | python3 -m json.tool
else
  curl -fsS "${MCP_URL}/tools" | python3 -m json.tool
fi

echo "==> Step 4: Granting run.servicesInvoker to Agent Gateway Service Agent..."
gcloud run services add-iam-policy-binding banking-mcp-server \
  --region="${LOCATION}" \
  --member="${AGW_SA}" \
  --role="roles/run.servicesInvoker" \
  --project="${PROJECT_ID}"

echo "==> Step 4 completed successfully."
