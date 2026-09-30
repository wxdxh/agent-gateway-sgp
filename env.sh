#!/usr/bin/env bash
# Central environment configuration for Enterprise Agent Governance Codelab

export PROJECT_ID="${PROJECT_ID:-$(gcloud config get-value project 2>/dev/null)}"
if [[ -z "${PROJECT_ID}" ]]; then
  echo "Error: PROJECT_ID is not set. Run 'gcloud config set project <PROJECT_ID>' or export PROJECT_ID=<...>"
  return 1 2>/dev/null || exit 1
fi

export PROJECT_NUM="$(gcloud projects describe "${PROJECT_ID}" --format="value(projectNumber)" 2>/dev/null)"
export LOCATION="${LOCATION:-us-central1}"
export AGW_SA="serviceAccount:service-${PROJECT_NUM}@gcp-sa-agentgateway.iam.gserviceaccount.com"

# Managed SGP Service Attachment in us-central1 (provided by Google)
export SERVICE_ATTACHMENT="projects/pb0cccf528857bbf1p-tp/regions/us-central1/serviceAttachments/k8s1-sa-xjw7b6ye-semantic-governanc-semantic-governanc-rokazjz2"

echo "=================================================="
echo " Project ID:     ${PROJECT_ID}"
echo " Project Number: ${PROJECT_NUM}"
echo " Location:       ${LOCATION}"
echo " Agent GW SA:    ${AGW_SA}"
echo "=================================================="
