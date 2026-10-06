#!/usr/bin/env bash
set -eo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "================================================================================"
echo " Google Cloud Gemini Enterprise Agent Governance (SGP) - End-to-End Deployment"
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

echo "--- 2. Provision Agent Gateway (Proxy Subnet, NA, agent-egress) ---"
"${SCRIPT_DIR}/02-setup-agent-gateway.sh"

echo "--- 3. Deploy Banking MCP Server to Cloud Run ---"
"${SCRIPT_DIR}/03-deploy-mcp.sh"

echo "--- 4. Register MCP Server & System Endpoints in Agent Registry ---"
"${SCRIPT_DIR}/04-register-mcp.sh"

echo "--- 5. Deploy Conversational Banking Agent to Gemini Enterprise ---"
"${SCRIPT_DIR}/05-deploy-agent.sh"

echo "--- 6. Provision SGP Private Service Connect (PSC) & Cloud DNS ---"
"${SCRIPT_DIR}/06-setup-sgp-networking.sh"

echo "--- 7. Configure Authz Extension, Authz Policy & Semantic Governance Policy ---"
"${SCRIPT_DIR}/07-create-sgp-policy.sh"

echo ""
echo "================================================================================"
echo " DEPLOYMENT FINISHED!"
echo "================================================================================"
"${SCRIPT_DIR}/08-test.sh"
