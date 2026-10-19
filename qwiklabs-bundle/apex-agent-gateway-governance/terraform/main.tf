# ============================================================================
# Qwiklabs Startup Script (main.tf)
# Lab: 에이펙스 금융그룹(Apex Financial Group) Agent Gateway 워크로드 거버넌스
# Pre-stages foundational APIs and Google-managed Service Agents at lab startup
# so that student Terraform + Skaffold deployment completes rapidly without
# IAM propagation delays or 409 naming collisions.
# ============================================================================

locals {
  required_apis = [
    "compute.googleapis.com",
    "run.googleapis.com",
    "artifactregistry.googleapis.com",
    "cloudbuild.googleapis.com",
    "networkservices.googleapis.com",
    "networksecurity.googleapis.com",
    "serviceextensions.googleapis.com",
    "iap.googleapis.com",
    "modelarmor.googleapis.com",
    "dlp.googleapis.com",
    "aiplatform.googleapis.com",
    "iam.googleapis.com",
    "cloudresourcemanager.googleapis.com",
    "dns.googleapis.com",
    "servicenetworking.googleapis.com",
    "storage.googleapis.com",
    "telemetry.googleapis.com",
    "cloudtrace.googleapis.com",
    "logging.googleapis.com",
    "monitoring.googleapis.com"
  ]
}

resource "google_project_service" "required_apis" {
  for_each           = toset(local.required_apis)
  project            = var.gcp_project_id
  service            = each.value
  disable_on_destroy = false
}

resource "google_project_service_identity" "aiplatform_sa" {
  provider   = google-beta
  project    = var.gcp_project_id
  service    = "aiplatform.googleapis.com"
  depends_on = [google_project_service.required_apis]
}

resource "google_project_service_identity" "dlp_sa" {
  provider   = google-beta
  project    = var.gcp_project_id
  service    = "dlp.googleapis.com"
  depends_on = [google_project_service.required_apis]
}
