output "gcp_project_id" {
  value       = var.gcp_project_id
  description = "The GCP Project ID provisioned for the Apex Asset Management lab."
}

output "gcp_region" {
  value       = var.gcp_region
  description = "The default GCP region for Agent Gateway, Cloud Run MCP, and SGP resources."
}

output "vpc_network_name" {
  value       = google_compute_network.apex_wealth_vpc.name
  description = "Pre-provisioned VPC network name (apex-wealth-vpc)."
}

output "vpc_subnet_name" {
  value       = google_compute_subnetwork.apex_subnet.name
  description = "Pre-provisioned regional subnet name (apex-subnet)."
}

output "lab_service_account" {
  value       = google_service_account.apex_lab_sa.email
  description = "Pre-provisioned service account email for the lab."
}
