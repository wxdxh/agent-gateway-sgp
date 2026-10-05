#!/usr/bin/env bash
set -eo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/env.sh"

echo "==> Step 6: Reserving internal static IP for SGP PSC endpoint..."
gcloud compute addresses create sgp-psc-ip \
  --region="${LOCATION}" \
  --subnet="${SUBNET_NAME}" \
  --purpose=GCE_ENDPOINT \
  --project="${PROJECT_ID}" || true

export PSC_IP="$(gcloud compute addresses describe sgp-psc-ip \
  --region="${LOCATION}" \
  --project="${PROJECT_ID}" \
  --format="value(address)")"
echo "PSC IP reserved: ${PSC_IP}"

echo "==> Step 6: Ensuring Semantic Governance Policy Engine is active and resolving service attachment..."
if [[ -z "${SERVICE_ATTACHMENT}" ]]; then
  SERVICE_ATTACHMENT="$(gcloud beta ai semantic-governance-policy-engine describe --location="${LOCATION}" --project="${PROJECT_ID}" --format="value(pscServiceAttachment)" 2>/dev/null || true)"
  if [[ -z "${SERVICE_ATTACHMENT}" ]]; then
    echo "Activating Semantic Governance Policy Engine in ${LOCATION}..."
    gcloud beta ai semantic-governance-policy-engine update --location="${LOCATION}" --project="${PROJECT_ID}" --quiet
    SERVICE_ATTACHMENT="$(gcloud beta ai semantic-governance-policy-engine describe --location="${LOCATION}" --project="${PROJECT_ID}" --format="value(pscServiceAttachment)" 2>/dev/null || true)"
  fi
fi

echo "Using SGP Service Attachment: ${SERVICE_ATTACHMENT}"

echo "==> Step 6: Creating PSC forwarding rule to SGP service attachment..."
gcloud compute forwarding-rules create sgp-psc-endpoint \
  --region="${LOCATION}" \
  --network="${NETWORK_NAME}" \
  --address="sgp-psc-ip" \
  --target-service-attachment="${SERVICE_ATTACHMENT}" \
  --project="${PROJECT_ID}" || true

echo "==> Step 6: Configuring private Cloud DNS for policy.internal..."
gcloud dns managed-zones create policy-engine-zone \
  --description="Private zone for internal SGP service" \
  --dns-name="policy.internal." \
  --visibility=private \
  --networks="${NETWORK_NAME}" \
  --project="${PROJECT_ID}" || true

gcloud dns record-sets create policy.internal. \
  --zone=policy-engine-zone \
  --type=A \
  --ttl=300 \
  --rrdatas="${PSC_IP}" \
  --project="${PROJECT_ID}" || true

echo "==> Step 6 completed successfully."
