#!/usr/bin/env bash
# Central environment configuration for Enterprise Agent Governance Codelab

export PATH="${HOME}/google-cloud-sdk/bin:${HOME}/.local/bin:${PATH}"

export PROJECT_ID="${PROJECT_ID:-$(gcloud config get-value project 2>/dev/null)}"
if [[ -z "${PROJECT_ID}" ]]; then
  echo "Error: PROJECT_ID is not set. Run 'gcloud config set project <PROJECT_ID>' or export PROJECT_ID=<...>"
  return 1 2>/dev/null || exit 1
fi

export PROJECT_NUM="$(gcloud projects describe "${PROJECT_ID}" --format="value(projectNumber)" 2>/dev/null)"
export LOCATION="${LOCATION:-us-central1}"
export AGW_SA="serviceAccount:service-${PROJECT_NUM}@gcp-sa-agentgateway.iam.gserviceaccount.com"

# Managed SGP Service Attachment (auto-detected from policy engine if empty)
export SERVICE_ATTACHMENT="${SERVICE_ATTACHMENT:-}"

# VPC Network and Subnet auto-detection (prefers pre-provisioned 'apex-wealth-vpc', then 'default', then active VPC)
if gcloud compute networks describe apex-wealth-vpc --project="${PROJECT_ID}" &>/dev/null; then
  DEFAULT_NET="apex-wealth-vpc"
  DEFAULT_SUBNET="apex-subnet"
elif gcloud compute networks describe default --project="${PROJECT_ID}" &>/dev/null; then
  DEFAULT_NET="default"
  DEFAULT_SUBNET="default"
else
  DEFAULT_NET="$(gcloud compute networks list --project="${PROJECT_ID}" --format="value(name)" 2>/dev/null | head -n 1)"
  DEFAULT_SUBNET="$(gcloud compute networks subnets list --project="${PROJECT_ID}" --regions="${LOCATION}" --network="${DEFAULT_NET}" --format="value(name)" 2>/dev/null | head -n 1)"
fi

export NETWORK_NAME="${NETWORK_NAME:-${DEFAULT_NET}}"
export SUBNET_NAME="${SUBNET_NAME:-${DEFAULT_SUBNET}}"

echo "=================================================="
echo " Project ID:     ${PROJECT_ID}"
echo " Project Number: ${PROJECT_NUM}"
echo " Location:       ${LOCATION}"
echo " VPC Network:    ${NETWORK_NAME}"
echo " VPC Subnet:     ${SUBNET_NAME}"
echo " Agent GW SA:    ${AGW_SA}"
echo "=================================================="
