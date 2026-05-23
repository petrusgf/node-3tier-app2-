output "gke_cluster_name" {
  description = "GKE cluster name"
  value       = module.gke.cluster_name
}

output "gke_cluster_endpoint" {
  description = "GKE cluster endpoint"
  value       = module.gke.cluster_endpoint
  sensitive   = true
}

output "artifact_registry_url" {
  description = "Artifact Registry Docker repository URL"
  value       = module.artifact_registry.registry_url
}

output "db_instance_name" {
  description = "Cloud SQL instance name"
  value       = module.cloud_sql.instance_name
}

output "db_private_ip" {
  description = "Cloud SQL private IP address"
  value       = module.cloud_sql.private_ip
  sensitive   = true
}

output "db_password_secret" {
  description = "Secret Manager secret name for DB password"
  value       = module.cloud_sql.password_secret_name
}

output "static_assets_bucket" {
  description = "GCS bucket for static assets (served via CDN)"
  value       = module.cdn.static_bucket_name
}

output "backup_bucket" {
  description = "GCS bucket for backups"
  value       = module.cdn.backup_bucket_name
}

output "kubeconfig_command" {
  description = "Command to configure kubectl"
  value       = "gcloud container clusters get-credentials ${module.gke.cluster_name} --region ${var.region} --project ${var.project_id}"
}

output "registry_url" {
  description = "Artifact Registry URL for Docker images"
  value       = module.artifact_registry.registry_url
}

output "cloudbuild_connect_command" {
  description = "Run this after connecting GitHub in Cloud Console to create the trigger"
  value       = "gcloud builds triggers create github --name=app-prod-deploy --repo-owner=${var.github_owner} --repo-name=${var.github_repo} --branch-pattern='^main$' --build-config=cloudbuild.yaml --region=${var.region} --project=${var.project_id}"
}
