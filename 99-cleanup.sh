#!/usr/bin/env bash
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/env.sh"

echo "==> Cleaning up resources created for Enterprise Agent Governance Codelab..."

echo "1. Deleting Semantic Governance Policy..."
gcloud beta ai semantic-governance-policies delete high-value-limit \
  --location="${LOCATION}" \
  --project="${PROJECT_ID}" \
  --quiet || true

echo "2. Deleting Cloud Run banking-mcp-server..."
gcloud run services delete banking-mcp-server \
  --region="${LOCATION}" \
  --project="${PROJECT_ID}" \
  --quiet || true

echo "3. Deleting Agent Registry MCP Server..."
gcloud alpha agent-registry services delete banking-mcp-server \
  --location="${LOCATION}" \
  --project="${PROJECT_ID}" \
  --quiet || true

echo "4. Deleting Authz Policy & Extension..."
gcloud beta network-security authz-policies delete agent-egress-sgp-authzpolicy \
  --location="${LOCATION}" \
  --project="${PROJECT_ID}" \
  --quiet || true

curl -s -X DELETE \
  "https://networkservices.googleapis.com/v1beta1/projects/${PROJECT_ID}/locations/${LOCATION}/authzExtensions/sgp-authzextension" \
  -H "Authorization: Bearer $(gcloud auth print-access-token)" || true

echo "5. Deleting Agent Gateway..."
gcloud network-services agent-gateways delete agent-egress \
  --location="${LOCATION}" \
  --project="${PROJECT_ID}" \
  --quiet || true

echo "6. Deleting DNS records and managed zone..."
gcloud dns record-sets delete policy.internal. \
  --zone=policy-engine-zone \
  --type=A \
  --project="${PROJECT_ID}" \
  --quiet || true

gcloud dns managed-zones delete policy-engine-zone \
  --project="${PROJECT_ID}" \
  --quiet || true

echo "7. Deleting PSC forwarding rule and address..."
gcloud compute forwarding-rules delete sgp-psc-endpoint \
  --region="${LOCATION}" \
  --project="${PROJECT_ID}" \
  --quiet || true

gcloud compute addresses delete sgp-psc-ip \
  --region="${LOCATION}" \
  --project="${PROJECT_ID}" \
  --quiet || true

echo "8. Deleting Network Attachment and proxy subnet..."
gcloud compute network-attachments delete agent-gateway-na \
  --region="${LOCATION}" \
  --project="${PROJECT_ID}" \
  --quiet || true

gcloud compute networks subnets delete proxy-only-subnet \
  --region="${LOCATION}" \
  --project="${PROJECT_ID}" \
  --quiet || true

echo "==> Cleanup completed."
