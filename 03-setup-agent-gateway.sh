#!/usr/bin/env bash
set -eo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/env.sh"

echo "==> Step 3: Generating Agent Gateway definition..."
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

echo "==> Step 3: Importing Agent Gateway resource..."
gcloud network-services agent-gateways import agent-egress \
  --source="${SCRIPT_DIR}/agent-gateway-vpc-egress.yaml" \
  --location="${LOCATION}" \
  --project="${PROJECT_ID}"

echo "==> Step 3: Registering SGP Authorization Extension..."
ACCESS_TOKEN="$(gcloud auth print-access-token)"
curl -fsS -X POST \
  "https://networkservices.googleapis.com/v1beta1/projects/${PROJECT_ID}/locations/${LOCATION}/authzExtensions?authzExtensionId=sgp-authzextension" \
  -H "Authorization: Bearer ${ACCESS_TOKEN}" \
  -H "Content-Type: application/json" \
  -d '{
    "service": "policy.internal",
    "authority": "policy.internal",
    "failOpen": false,
    "loadBalancingScheme": "LOAD_BALANCING_SCHEME_UNSPECIFIED"
  }' || echo "Note: Authz extension might already exist."

echo "==> Step 3: Generating Content Authorization Policy definition..."
cat > "${SCRIPT_DIR}/agent-egress-sgp-authzpolicy.yaml" << YAML_EOF
name: projects/${PROJECT_ID}/locations/${LOCATION}/authzPolicies/agent-egress-sgp-authzpolicy
target:
  loadBalancingScheme: LOAD_BALANCING_SCHEME_UNSPECIFIED
  resources:
    - "projects/${PROJECT_NUM}/locations/${LOCATION}/agentGateways/agent-egress"
httpRules:
  - to:
      operations:
        - paths:
            - prefix: "/"
    when: '!request.headers["content-type"].startsWith("application/grpc") && (request.path.endsWith(":generateContent") || request.path.endsWith(":streamGenerateContent"))'
action: CUSTOM
policyProfile: CONTENT_AUTHZ
customProvider:
  authzExtension:
    resources:
      - "projects/${PROJECT_NUM}/locations/${LOCATION}/authzExtensions/sgp-authzextension"
YAML_EOF

echo "==> Step 3: Importing Content Authorization Policy..."
gcloud beta network-security authz-policies import agent-egress-sgp-authzpolicy \
  --source="${SCRIPT_DIR}/agent-egress-sgp-authzpolicy.yaml" \
  --location="${LOCATION}" \
  --project="${PROJECT_ID}"

echo "==> Step 3 completed successfully."
