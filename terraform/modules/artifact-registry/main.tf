resource "google_artifact_registry_repository" "app" {
  location      = var.region
  repository_id = "${var.prefix}-app"
  description   = "Docker images for 3-tier app"
  format        = "DOCKER"
  project       = var.project_id

  labels = {
    environment = var.prefix
    managed-by  = "terraform"
  }
}

# Grant the Cloud Build default SA permission to push images
resource "google_artifact_registry_repository_iam_member" "cloudbuild_writer" {
  location   = google_artifact_registry_repository.app.location
  repository = google_artifact_registry_repository.app.name
  role       = "roles/artifactregistry.writer"
  member     = "serviceAccount:${data.google_project.project.number}@cloudbuild.gserviceaccount.com"
  project    = var.project_id
}

# Allow Cloud Build SA to deploy to GKE
resource "google_project_iam_member" "cloudbuild_gke" {
  project = var.project_id
  role    = "roles/container.developer"
  member  = "serviceAccount:${data.google_project.project.number}@cloudbuild.gserviceaccount.com"
}

# Allow Cloud Build SA to read secrets (DB credentials)
resource "google_project_iam_member" "cloudbuild_secrets" {
  project = var.project_id
  role    = "roles/secretmanager.secretAccessor"
  member  = "serviceAccount:${data.google_project.project.number}@cloudbuild.gserviceaccount.com"
}

data "google_project" "project" {
  project_id = var.project_id
}
