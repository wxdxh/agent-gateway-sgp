#!/usr/bin/env bash
set -eo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/env.sh"

echo "==> Step 2: Creating regional proxy-only subnet..."
gcloud compute networks subnets create proxy-only-subnet \
  --network=default \
  --region="${LOCATION}" \
  --range="10.11.13.0/24" \
  --purpose=REGIONAL_MANAGED_PROXY \
  --role=ACTIVE \
  --project="${PROJECT_ID}" || true

echo "==> Step 2: Creating Network Attachment for Agent Gateway..."
gcloud compute network-attachments create agent-gateway-na \
  --region="${LOCATION}" \
  --subnets=default \
  --connection-preference=ACCEPT_AUTOMATIC \
  --project="${PROJECT_ID}" || true

echo "==> Step 2: Reserving internal static IP for PSC endpoint..."
gcloud compute addresses create sgp-psc-ip \
  --region="${LOCATION}" \
  --subnet=default \
  --purpose=GCE_ENDPOINT \
  --project="${PROJECT_ID}" || true

export PSC_IP="$(gcloud compute addresses describe sgp-psc-ip \
  --region="${LOCATION}" \
  --project="${PROJECT_ID}" \
  --format="value(address)")"
echo "PSC IP reserved: ${PSC_IP}"

echo "==> Step 2: Creating PSC forwarding rule to SGP service attachment..."
gcloud compute forwarding-rules create sgp-psc-endpoint \
  --region="${LOCATION}" \
  --network=default \
  --address="${PSC_IP}" \
  --target-service-attachment="${SERVICE_ATTACHMENT}" \
  --project="${PROJECT_ID}" || true

echo "==> Step 2: Configuring private Cloud DNS for policy.internal..."
gcloud dns managed-zones create policy-engine-zone \
  --description="Private zone for internal SGP service" \
  --dns-name="policy.internal." \
  --visibility=private \
  --networks=default \
  --project="${PROJECT_ID}" || true

gcloud dns record-sets create policy.internal. \
  --zone=policy-engine-zone \
  --type=A \
  --ttl=300 \
  --rrdatas="${PSC_IP}" \
  --project="${PROJECT_ID}" || true

echo "==> Step 2 completed successfully."
