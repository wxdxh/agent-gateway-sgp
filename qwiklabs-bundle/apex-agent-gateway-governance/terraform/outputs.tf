output "gcp_project_id" {
  value       = var.gcp_project_id
  description = "The GCP Project ID provisioned for the Apex Mortgage Governance lab."
}

output "gcp_region" {
  value       = var.gcp_region
  description = "The default GCP region for Agent Gateway, Cloud Run MCP, IAP, and Model Armor resources."
}
