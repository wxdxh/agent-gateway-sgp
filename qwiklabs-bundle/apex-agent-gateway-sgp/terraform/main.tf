# ============================================================================
# Qwiklabs Startup Script (main.tf)
# Lab: 에이펙스 자산운용(Apex Asset Management) 엔터프라이즈 AI 에이전트 거버넌스
# Stages foundational resources at lab startup:
#   1. All 19 Required Google Cloud APIs
#   2. Google-managed Service Agents (Network Services / Agent Gateway, Vertex AI) & IAM Bindings
#   3. Custom VPC Network (apex-wealth-vpc), Regional Subnet (apex-subnet), and Proxy-Only Subnet (proxy-only-subnet)
#   4. Private Cloud DNS Zone (policy-engine-zone) and Internal PSC Static IP (sgp-psc-ip)
#   5. Foundational Lab Service Account & IAM Role Bindings
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
    "agentregistry.googleapis.com",
    "aiplatform.googleapis.com",
    "run.googleapis.com",
    "cloudbuild.googleapis.com",
    "artifactregistry.googleapis.com",
    "storage.googleapis.com",
    "modelarmor.googleapis.com",
    "telemetry.googleapis.com",
    "cloudtrace.googleapis.com",
    "logging.googleapis.com",
    "cloudapiregistry.googleapis.com",
    "agentidentity.googleapis.com",
    "serviceextensions.googleapis.com"
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

# 2. Pre-create Vertex AI Service Identity at lab startup (IAM roles bound in Step 1 after propagation)
resource "google_project_service_identity" "aiplatform_sa" {
  provider   = google-beta
  project    = var.gcp_project_id
  service    = "aiplatform.googleapis.com"
  depends_on = [google_project_service.required_apis]
}

# 3. Provision Custom VPC Network, Regional Subnet & Managed Proxy-Only Subnet
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

resource "google_compute_subnetwork" "proxy_only_subnet" {
  name          = "proxy-only-subnet"
  ip_cidr_range = "10.11.13.0/24"
  region        = var.gcp_region
  network       = google_compute_network.apex_wealth_vpc.id
  purpose       = "REGIONAL_MANAGED_PROXY"
  role          = "ACTIVE"
  project       = var.gcp_project_id
  description   = "Regional managed proxy subnet for Agent Gateway Envoy proxies"
}

# 4. Provision Private Cloud DNS Zone (policy.internal.) & Internal Static IP (sgp-psc-ip)
resource "google_dns_managed_zone" "policy_engine_zone" {
  name        = "policy-engine-zone"
  dns_name    = "policy.internal."
  description = "Private zone for internal SGP service"
  visibility  = "private"
  project     = var.gcp_project_id

  private_visibility_config {
    networks {
      network_url = google_compute_network.apex_wealth_vpc.id
    }
  }
}

resource "google_compute_address" "sgp_psc_ip" {
  name         = "sgp-psc-ip"
  region       = var.gcp_region
  subnetwork   = google_compute_subnetwork.apex_subnet.id
  address_type = "INTERNAL"
  purpose      = "GCE_ENDPOINT"
  project      = var.gcp_project_id
  description  = "Internal static IP for SGP Private Service Connect endpoint"
}

# 5. Provision Foundational Service Account & IAM Bindings
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
