#!/usr/bin/env bash
set -eo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/env.sh"

echo "==> Step 6: Verifying internal static IP (sgp-psc-ip) for SGP PSC endpoint..."
if ! gcloud compute addresses describe sgp-psc-ip --region="${LOCATION}" --project="${PROJECT_ID}" &>/dev/null; then
  gcloud compute addresses create sgp-psc-ip \
    --region="${LOCATION}" \
    --subnet="${SUBNET_NAME}" \
    --purpose=GCE_ENDPOINT \
    --project="${PROJECT_ID}" || true
fi

export PSC_IP="$(gcloud compute addresses describe sgp-psc-ip \
  --region="${LOCATION}" \
  --project="${PROJECT_ID}" \
  --format="value(address)")"
echo "PSC IP reserved: ${PSC_IP}"

echo "==> Step 6: Ensuring Semantic Governance Policy Engine is active and resolving service attachment..."
if [[ -z "${SERVICE_ATTACHMENT}" ]]; then
  if { [[ -f /tmp/sgp-engine-warmup.pid ]] && kill -0 "$(cat /tmp/sgp-engine-warmup.pid)" 2>/dev/null; } || pgrep -f "semantic-governance-policy-engine update" >/dev/null 2>&1; then
    echo "Waiting for background SGP Engine warm-up started in Step 1 to finish..."
    while { [[ -f /tmp/sgp-engine-warmup.pid ]] && kill -0 "$(cat /tmp/sgp-engine-warmup.pid)" 2>/dev/null; } || pgrep -f "semantic-governance-policy-engine update" >/dev/null 2>&1; do
      sleep 3
    done
  fi
  SERVICE_ATTACHMENT="$(gcloud beta ai semantic-governance-policy-engine describe --location="${LOCATION}" --project="${PROJECT_ID}" --format="value(pscServiceAttachment)" 2>/dev/null || true)"
  if [[ -z "${SERVICE_ATTACHMENT}" ]]; then
    echo "Activating Semantic Governance Policy Engine in ${LOCATION}..."
    gcloud beta ai semantic-governance-policy-engine update --location="${LOCATION}" --project="${PROJECT_ID}" --quiet
    SERVICE_ATTACHMENT="$(gcloud beta ai semantic-governance-policy-engine describe --location="${LOCATION}" --project="${PROJECT_ID}" --format="value(pscServiceAttachment)" 2>/dev/null || true)"
  fi
fi

echo "Using SGP Service Attachment: ${SERVICE_ATTACHMENT}"

echo "==> Step 6: Creating PSC forwarding rule to SGP service attachment..."
if ! gcloud compute forwarding-rules describe sgp-psc-endpoint --region="${LOCATION}" --project="${PROJECT_ID}" &>/dev/null; then
  gcloud compute forwarding-rules create sgp-psc-endpoint \
    --region="${LOCATION}" \
    --network="${NETWORK_NAME}" \
    --address="sgp-psc-ip" \
    --target-service-attachment="${SERVICE_ATTACHMENT}" \
    --project="${PROJECT_ID}" || true
else
  echo "sgp-psc-endpoint already exists."
fi

echo "==> Step 6: Configuring private Cloud DNS A record for policy.internal..."
if ! gcloud dns managed-zones describe policy-engine-zone --project="${PROJECT_ID}" &>/dev/null; then
  gcloud dns managed-zones create policy-engine-zone \
    --description="Private zone for internal SGP service" \
    --dns-name="policy.internal." \
    --visibility=private \
    --networks="${NETWORK_NAME}" \
    --project="${PROJECT_ID}" || true
fi

if ! gcloud dns record-sets describe policy.internal. --zone=policy-engine-zone --type=A --project="${PROJECT_ID}" &>/dev/null; then
  gcloud dns record-sets create policy.internal. \
    --zone=policy-engine-zone \
    --type=A \
    --ttl=300 \
    --rrdatas="${PSC_IP}" \
    --project="${PROJECT_ID}" || true
else
  echo "DNS A record for policy.internal. already exists."
fi

echo "==> Step 6 completed successfully."
