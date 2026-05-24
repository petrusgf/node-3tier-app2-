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

data "google_project" "project" {
  project_id = var.project_id
}

locals {
  # Cloud Build trigger is configured to run as the Compute Engine default SA.
  # Format: PROJECT_NUMBER-compute@developer.gserviceaccount.com
  cloudbuild_sa = "serviceAccount:${data.google_project.project.number}-compute@developer.gserviceaccount.com"
}

# Allow Cloud Build SA to push images to Artifact Registry
resource "google_artifact_registry_repository_iam_member" "cloudbuild_writer" {
  location   = google_artifact_registry_repository.app.location
  repository = google_artifact_registry_repository.app.name
  role       = "roles/artifactregistry.writer"
  member     = local.cloudbuild_sa
  project    = var.project_id
}

# Allow Cloud Build SA to deploy to GKE
resource "google_project_iam_member" "cloudbuild_gke" {
  project = var.project_id
  role    = "roles/container.developer"
  member  = local.cloudbuild_sa
}

# Allow Cloud Build SA to read secrets (DB credentials at deploy time)
resource "google_project_iam_member" "cloudbuild_secrets" {
  project = var.project_id
  role    = "roles/secretmanager.secretAccessor"
  member  = local.cloudbuild_sa
}
