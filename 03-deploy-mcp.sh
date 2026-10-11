#!/usr/bin/env bash
set -eo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/env.sh"

echo "==> Step 3: Checking or deploying banking-mcp-server on Cloud Run..."
export MCP_URL="$(gcloud run services describe banking-mcp-server \
  --region="${LOCATION}" \
  --project="${PROJECT_ID}" \
  --format="value(status.url)" 2>/dev/null || true)"

if [[ -z "${MCP_URL}" ]]; then
  if { [[ -f /tmp/banking-mcp-warmup.pid ]] && kill -0 "$(cat /tmp/banking-mcp-warmup.pid)" 2>/dev/null; } || pgrep -f "run deploy banking-mcp-server" >/dev/null 2>&1; then
    echo "Waiting for background banking-mcp-server deployment started in Step 1 to finish..."
    while { [[ -f /tmp/banking-mcp-warmup.pid ]] && kill -0 "$(cat /tmp/banking-mcp-warmup.pid)" 2>/dev/null; } || pgrep -f "run deploy banking-mcp-server" >/dev/null 2>&1; do
      sleep 5
    done
    export MCP_URL="$(gcloud run services describe banking-mcp-server \
      --region="${LOCATION}" \
      --project="${PROJECT_ID}" \
      --format="value(status.url)" 2>/dev/null || true)"
  fi
fi

if [[ -z "${MCP_URL}" ]]; then
  cd "${SCRIPT_DIR}/banking-mcp-server"
  gcloud run deploy banking-mcp-server \
    --source=. \
    --region="${LOCATION}" \
    --project="${PROJECT_ID}" \
    --allow-unauthenticated \
    --quiet
  cd "${SCRIPT_DIR}"
  export MCP_URL="$(gcloud run services describe banking-mcp-server \
    --region="${LOCATION}" \
    --project="${PROJECT_ID}" \
    --format="value(status.url)")"
else
  echo "banking-mcp-server is already deployed and ready."
fi

echo "=================================================="
echo " Banking MCP Server URL: ${MCP_URL}"
echo "=================================================="
echo "export MCP_URL=\"${MCP_URL}\"" >> "${SCRIPT_DIR}/.env.runtime"

echo "==> Step 3: Verifying /tools endpoint..."
ID_TOKEN="$(gcloud auth print-identity-token 2>/dev/null || true)"
if [ -n "${ID_TOKEN}" ]; then
  curl -fsS -H "Authorization: Bearer ${ID_TOKEN}" "${MCP_URL}/tools" | python3 -m json.tool
else
  curl -fsS "${MCP_URL}/tools" | python3 -m json.tool
fi

echo "==> Step 3: Granting run.servicesInvoker to Agent Gateway Service Agent..."
gcloud run services add-iam-policy-binding banking-mcp-server \
  --region="${LOCATION}" \
  --member="${AGW_SA}" \
  --role="roles/run.servicesInvoker" \
  --project="${PROJECT_ID}"

gcloud run services add-iam-policy-binding banking-mcp-server \
  --region="${LOCATION}" \
  --member="serviceAccount:service-${PROJECT_NUM}@gcp-sa-aiplatform-re.iam.gserviceaccount.com" \
  --role="roles/run.servicesInvoker" \
  --project="${PROJECT_ID}" \
  --quiet >/dev/null 2>&1 || true

echo "==> Step 3 completed successfully."
