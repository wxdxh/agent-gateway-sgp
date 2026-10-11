#!/usr/bin/env bash
set -eo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/env.sh"

echo "==> Step 1: Verifying and enabling required Google Cloud APIs..."
gcloud services enable \
  compute.googleapis.com \
  networksecurity.googleapis.com \
  networkservices.googleapis.com \
  dns.googleapis.com \
  iam.googleapis.com \
  iap.googleapis.com \
  agentregistry.googleapis.com \
  aiplatform.googleapis.com \
  run.googleapis.com \
  cloudbuild.googleapis.com \
  artifactregistry.googleapis.com \
  storage.googleapis.com \
  modelarmor.googleapis.com \
  telemetry.googleapis.com \
  cloudtrace.googleapis.com \
  logging.googleapis.com \
  cloudapiregistry.googleapis.com \
  agentidentity.googleapis.com \
  serviceextensions.googleapis.com \
  --project="${PROJECT_ID}"

echo "==> Step 1: Ensuring Network Services and Vertex AI service identities..."
gcloud beta services identity create \
  --service=networkservices.googleapis.com \
  --project="${PROJECT_ID}" || true

gcloud beta services identity create \
  --service=aiplatform.googleapis.com \
  --project="${PROJECT_ID}" || true

for ROLE in "roles/aiplatform.serviceAgent" "roles/aiplatform.user" "roles/agentregistry.viewer"; do
  gcloud projects add-iam-policy-binding "${PROJECT_ID}" \
    --member="serviceAccount:service-${PROJECT_NUM}@gcp-sa-aiplatform.iam.gserviceaccount.com" \
    --role="${ROLE}" \
    --condition=None \
    --quiet >/dev/null 2>&1 || true
done

echo "==> Step 1: Granting IAM roles to Agent Gateway Service Agent..."
for ROLE in "roles/agentgateway.serviceAgent" "roles/aiplatform.user" "roles/modelarmor.user" "roles/agentregistry.viewer"; do
  echo "Granting ${ROLE} to ${AGW_SA}..."
  gcloud projects add-iam-policy-binding "${PROJECT_ID}" \
    --member="${AGW_SA}" \
    --role="${ROLE}" \
    --condition=None \
    --quiet >/dev/null
done

echo "==> Step 1: Verifying Cloud Shell CLI tools (uv & google-agents-cli)..."
if ! command -v uv &>/dev/null; then
  echo "Installing uv..."
  curl -LsSf https://astral.sh/uv/install.sh | sh
  export PATH="${HOME}/.local/bin:${PATH}"
fi

if ! command -v agents-cli &>/dev/null; then
  echo "Installing google-agents-cli..."
  uv tool install google-agents-cli
  export PATH="${HOME}/.local/bin:${PATH}"
fi

echo "==> Step 1: Pre-creating Conversational Banking Agent Identity (C-1 Optimization)..."
TOKEN="$(gcloud auth print-access-token)"
EFFECTIVE_ID="$(curl -fsS -H "Authorization: Bearer ${TOKEN}" \
  "https://${LOCATION}-aiplatform.googleapis.com/v1beta1/projects/${PROJECT_ID}/locations/${LOCATION}/reasoningEngines" 2>/dev/null | \
  python3 -c 'import sys, json; engines=json.load(sys.stdin).get("reasoningEngines", []); matches=[e for e in engines if e.get("displayName")=="conversational-banking"]; print(matches[0].get("spec", {}).get("effectiveIdentity", "") if matches else "")' 2>/dev/null || true)"

if [[ -z "${EFFECTIVE_ID}" ]]; then
  curl -fsS -X POST \
    "https://${LOCATION}-aiplatform.googleapis.com/v1beta1/projects/${PROJECT_ID}/locations/${LOCATION}/reasoningEngines" \
    -H "Authorization: Bearer ${TOKEN}" \
    -H "Content-Type: application/json" \
    -d '{"displayName": "conversational-banking", "spec": {"identityType": "AGENT_IDENTITY"}}' >/dev/null 2>&1 || true

  for _i in 1 2 3 4 5; do
    sleep 3
    EFFECTIVE_ID="$(curl -fsS -H "Authorization: Bearer ${TOKEN}" \
      "https://${LOCATION}-aiplatform.googleapis.com/v1beta1/projects/${PROJECT_ID}/locations/${LOCATION}/reasoningEngines" 2>/dev/null | \
      python3 -c 'import sys, json; engines=json.load(sys.stdin).get("reasoningEngines", []); matches=[e for e in engines if e.get("displayName")=="conversational-banking"]; print(matches[0].get("spec", {}).get("effectiveIdentity", "") if matches else "")' 2>/dev/null || true)"
    [[ -n "${EFFECTIVE_ID}" ]] && break
  done
fi

if [[ -n "${EFFECTIVE_ID}" ]]; then
  AGENT_PRINCIPAL="principal://${EFFECTIVE_ID}"
  echo "Pre-provisioned Agent Identity: ${AGENT_PRINCIPAL}"
  for ROLE in \
    "roles/agentregistry.viewer" \
    "roles/agentregistry.user" \
    "roles/aiplatform.user" \
    "roles/serviceusage.serviceUsageConsumer" \
    "roles/cloudapiregistry.viewer" \
    "roles/logging.logWriter" \
    "roles/monitoring.metricWriter"; do
    gcloud projects add-iam-policy-binding "${PROJECT_ID}" \
      --member="${AGENT_PRINCIPAL}" \
      --role="${ROLE}" \
      --condition=None \
      --quiet >/dev/null 2>&1 || true
  done
fi

RE_SA="serviceAccount:service-${PROJECT_NUM}@gcp-sa-aiplatform-re.iam.gserviceaccount.com"
for ROLE in "roles/aiplatform.serviceAgent" "roles/agentregistry.viewer" "roles/aiplatform.user"; do
  gcloud projects add-iam-policy-binding "${PROJECT_ID}" \
    --member="${RE_SA}" \
    --role="${ROLE}" \
    --condition=None \
    --quiet >/dev/null 2>&1 || true
done

echo "==> Step 1: Triggering background warm-up for Cloud Run MCP Server and SGP Engine..."
if ! gcloud run services describe banking-mcp-server --region="${LOCATION}" --project="${PROJECT_ID}" &>/dev/null; then
  nohup gcloud run deploy banking-mcp-server \
    --source="${SCRIPT_DIR}/banking-mcp-server" \
    --region="${LOCATION}" \
    --project="${PROJECT_ID}" \
    --allow-unauthenticated \
    --quiet >/tmp/banking-mcp-warmup.log 2>&1 &
  echo $! >/tmp/banking-mcp-warmup.pid
fi

if [[ -z "$(gcloud beta ai semantic-governance-policy-engine describe --location="${LOCATION}" --project="${PROJECT_ID}" --format="value(pscServiceAttachment)" 2>/dev/null || true)" ]]; then
  nohup gcloud beta ai semantic-governance-policy-engine update \
    --location="${LOCATION}" \
    --project="${PROJECT_ID}" \
    --quiet >/tmp/sgp-engine-warmup.log 2>&1 &
  echo $! >/tmp/sgp-engine-warmup.pid
fi

echo "==> Step 1 completed successfully."
