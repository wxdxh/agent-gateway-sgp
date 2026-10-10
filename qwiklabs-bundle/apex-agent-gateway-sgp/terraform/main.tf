# ============================================================================
# Qwiklabs Startup Script (main.tf)
# Lab: 에이펙스 자산운용(Apex Asset Management) 엔터프라이즈 AI 에이전트 거버넌스
# Stages foundational resources at lab startup:
#   1. Core Google Cloud APIs
#   2. Custom VPC Network (apex-wealth-vpc) and Regional Subnet (apex-subnet)
#   3. Foundational Lab Service Account & IAM Role Bindings
# ============================================================================

data "google_project" "project" {
  project_id = var.gcp_project_id
}

# 1. Enable foundational Google Cloud APIs
locals {
  required_apis = [
    "compute.googleapis.com",
    "networksecurity.googleapis.com",
    "networkservices.googleapis.com",
    "dns.googleapis.com",
    "iam.googleapis.com",
    "iap.googleapis.com",
    "aiplatform.googleapis.com",
    "run.googleapis.com",
    "cloudbuild.googleapis.com",
    "artifactregistry.googleapis.com",
    "storage.googleapis.com",
    "cloudtrace.googleapis.com",
    "logging.googleapis.com"
  ]

  lab_iam_roles = [
    "roles/aiplatform.user",
    "roles/run.admin",
    "roles/cloudbuild.builds.editor",
    "roles/dns.admin"
  ]
}

resource "google_project_service" "required_apis" {
  for_each           = toset(local.required_apis)
  project            = var.gcp_project_id
  service            = each.value
  disable_on_destroy = false
}

# 2. Provision Custom VPC Network & Regional Subnet for Apex Asset Management
resource "google_compute_network" "apex_wealth_vpc" {
  name                    = "apex-wealth-vpc"
  auto_create_subnetworks = false
  project                 = var.gcp_project_id
  description             = "VPC network for Apex Asset Management Agent Gateway and SGP lab"
  depends_on              = [google_project_service.required_apis]
}

resource "google_compute_subnetwork" "apex_subnet" {
  name          = "apex-subnet"
  ip_cidr_range = "10.10.0.0/24"
  region        = var.gcp_region
  network       = google_compute_network.apex_wealth_vpc.id
  project       = var.gcp_project_id
  description   = "Regional subnet for Agent Gateway Network Attachment and SGP PSC endpoint"
}

# 3. Provision Foundational Service Account & IAM Bindings
resource "google_service_account" "apex_lab_sa" {
  account_id   = "apex-agent-lab-sa"
  display_name = "Apex Asset Management Lab Service Account"
  project      = var.gcp_project_id
  depends_on   = [google_project_service.required_apis]
}

resource "google_project_iam_member" "apex_lab_sa_roles" {
  for_each = toset(local.lab_iam_roles)
  project  = var.gcp_project_id
  role     = each.value
  member   = "serviceAccount:${google_service_account.apex_lab_sa.email}"
}
