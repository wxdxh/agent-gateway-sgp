#!/usr/bin/env bash
set -eo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/env.sh"

if [[ -z "${NETWORK_NAME}" ]]; then
  echo "==> Creating VPC network apex-wealth-vpc and subnet apex-subnet..."
  export NETWORK_NAME="apex-wealth-vpc"
  export SUBNET_NAME="apex-subnet"
  gcloud compute networks create "${NETWORK_NAME}" --subnet-mode=custom --project="${PROJECT_ID}" || true
  gcloud compute networks subnets create "${SUBNET_NAME}" \
    --network="${NETWORK_NAME}" \
    --region="${LOCATION}" \
    --range="10.10.0.0/24" \
    --project="${PROJECT_ID}" || true
fi

echo "==> Step 2: Creating regional proxy-only subnet in ${NETWORK_NAME}..."
gcloud compute networks subnets create proxy-only-subnet \
  --network="${NETWORK_NAME}" \
  --region="${LOCATION}" \
  --range="10.11.13.0/24" \
  --purpose=REGIONAL_MANAGED_PROXY \
  --role=ACTIVE \
  --project="${PROJECT_ID}" || true

echo "==> Step 2: Creating Network Attachment for Agent Gateway..."
gcloud compute network-attachments create agent-gateway-na \
  --region="${LOCATION}" \
  --subnets="${SUBNET_NAME}" \
  --connection-preference=ACCEPT_AUTOMATIC \
  --project="${PROJECT_ID}" || true

echo "==> Step 2: Generating Agent Gateway definition..."
cat > "${SCRIPT_DIR}/agent-gateway-vpc-egress.yaml" << YAML_EOF
name: projects/${PROJECT_ID}/locations/${LOCATION}/agentGateways/agent-egress
protocols:
  - MCP
googleManaged:
  governedAccessPath: AGENT_TO_ANYWHERE
registries:
  - //agentregistry.googleapis.com/projects/${PROJECT_ID}/locations/${LOCATION}
networkConfig:
  egress:
    networkAttachment: projects/${PROJECT_ID}/regions/${LOCATION}/networkAttachments/agent-gateway-na
  dnsPeeringConfig:
    domains:
      - policy.internal.
    targetProject: ${PROJECT_ID}
    targetNetwork: projects/${PROJECT_ID}/global/networks/${NETWORK_NAME}
YAML_EOF

echo "==> Step 2: Importing Agent Gateway resource (agent-egress)..."
gcloud network-services agent-gateways import agent-egress \
  --source="${SCRIPT_DIR}/agent-gateway-vpc-egress.yaml" \
  --location="${LOCATION}" \
  --project="${PROJECT_ID}"

echo "==> Step 2 completed successfully."
