#!/usr/bin/env bash
set -eo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "================================================================================"
echo " Google Cloud Enterprise Agent Governance (SGP) - End-to-End Deployment"
echo "================================================================================"
source "${SCRIPT_DIR}/env.sh"

read -p "Proceed with deployment to GCP project '${PROJECT_ID}' in region '${LOCATION}'? (y/N) " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
  echo "Aborted by user."
  exit 0
fi

echo "--- 1. Setup Environment & IAM ---"
"${SCRIPT_DIR}/01-setup-env.sh"

echo "--- 2. Provision Networking (Subnet, NA, PSC, DNS) ---"
"${SCRIPT_DIR}/02-setup-networking.sh"

echo "--- 3. Provision Agent Gateway & Authz Policy ---"
"${SCRIPT_DIR}/03-setup-agent-gateway.sh"

echo "--- 4. Deploy Banking MCP Server to Cloud Run ---"
"${SCRIPT_DIR}/04-deploy-mcp.sh"

echo "--- 5. Register MCP Server in Agent Registry ---"
"${SCRIPT_DIR}/05-register-mcp.sh"

echo "--- 6. Deploy Conversational Banking Agent ---"
"${SCRIPT_DIR}/06-deploy-agent.sh"

echo "--- 7. Create Semantic Governance Policy ---"
"${SCRIPT_DIR}/07-create-sgp-policy.sh"

echo ""
echo "================================================================================"
echo " DEPLOYMENT FINISHED!"
echo "================================================================================"
"${SCRIPT_DIR}/08-test.sh"
