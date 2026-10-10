#!/usr/bin/env bash
set -eo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/env.sh"

echo "==> Step 1: Enabling required APIs..."
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
  --project="${PROJECT_ID}"

echo "==> Step 1: Creating Network Services and Vertex AI service identities..."
gcloud beta services identity create \
  --service=networkservices.googleapis.com \
  --project="${PROJECT_ID}" || true

gcloud beta services identity create \
  --service=aiplatform.googleapis.com \
  --project="${PROJECT_ID}" || true

gcloud projects add-iam-policy-binding "${PROJECT_ID}" \
  --member="serviceAccount:service-${PROJECT_NUM}@gcp-sa-aiplatform.iam.gserviceaccount.com" \
  --role="roles/aiplatform.serviceAgent" \
  --condition=None \
  --quiet >/dev/null 2>&1 || true

echo "==> Step 1: Granting IAM roles to Agent Gateway Service Agent..."
for ROLE in "roles/agentgateway.serviceAgent" "roles/aiplatform.user" "roles/modelarmor.user" "roles/agentregistry.viewer"; do
  echo "Granting ${ROLE} to ${AGW_SA}..."
  gcloud projects add-iam-policy-binding "${PROJECT_ID}" \
    --member="${AGW_SA}" \
    --role="${ROLE}" \
    --condition=None \
    --quiet
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

echo "==> Step 1 completed successfully."
