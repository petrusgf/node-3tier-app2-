output "registry_id" {
  value = google_artifact_registry_repository.app.id
}

output "registry_url" {
  value = "${var.region}-docker.pkg.dev/${var.project_id}/${google_artifact_registry_repository.app.repository_id}"
}
