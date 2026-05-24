provider "google" {
  project = var.project_id
  region  = var.region
}

provider "google-beta" {
  project = var.project_id
  region  = var.region
}

# Enable required APIs
resource "google_project_service" "apis" {
  for_each = toset([
    "compute.googleapis.com",
    "container.googleapis.com",
    "sqladmin.googleapis.com",
    "servicenetworking.googleapis.com",
    "secretmanager.googleapis.com",
    "artifactregistry.googleapis.com",
    "cloudscheduler.googleapis.com",
    "cloudbuild.googleapis.com",
    "monitoring.googleapis.com",
    "logging.googleapis.com",
  ])

  service            = each.value
  disable_on_destroy = false
}

module "vpc" {
  source = "./modules/vpc"

  project_id = var.project_id
  region     = var.region
  prefix     = "${var.prefix}-${var.environment}"

  depends_on = [google_project_service.apis]
}

module "artifact_registry" {
  source = "./modules/artifact-registry"

  project_id = var.project_id
  region     = var.region
  prefix     = "${var.prefix}-${var.environment}"

  depends_on = [google_project_service.apis]
}

module "gke" {
  source = "./modules/gke"

  project_id     = var.project_id
  region         = var.region
  prefix         = "${var.prefix}-${var.environment}"
  network_id     = module.vpc.network_id
  subnetwork_id  = module.vpc.gke_subnetwork_id
  machine_type   = var.gke_machine_type
  min_node_count = var.gke_min_node_count
  max_node_count = var.gke_max_node_count
  registry_id    = module.artifact_registry.registry_id
  location       = var.gke_location

  depends_on = [module.vpc, module.artifact_registry]
}

module "cloud_sql" {
  source = "./modules/cloud-sql"

  project_id             = var.project_id
  region                 = var.region
  prefix                 = "${var.prefix}-${var.environment}"
  network_id             = module.vpc.network_id
  private_vpc_connection = module.vpc.private_vpc_connection
  db_tier                = var.db_tier
  db_name                = var.db_name
  db_user                = var.db_user
  backup_bucket_name     = module.cdn.backup_bucket_name
  db_availability_type   = var.db_availability_type

  depends_on = [module.vpc]
}

module "cdn" {
  source = "./modules/cdn"

  project_id             = var.project_id
  region                 = var.region
  prefix                 = "${var.prefix}-${var.environment}"
  web_domain             = var.web_domain
  api_domain             = var.api_domain
  backup_bucket_location = var.backup_bucket_location

  depends_on = [google_project_service.apis]
}

module "monitoring" {
  source = "./modules/monitoring"

  project_id               = var.project_id
  region                   = var.region
  prefix                   = "${var.prefix}-${var.environment}"
  cluster_name             = module.gke.cluster_name
  sql_instance_name        = module.cloud_sql.instance_name
  alert_notification_email = var.alert_notification_email
  web_domain               = var.web_domain
  api_domain               = var.api_domain

  depends_on = [module.gke, module.cloud_sql]
}

# Cloud Build trigger — created manually after connecting GitHub in Cloud Console.
# Once GitHub is connected, run:
#   gcloud builds triggers create github \
#     --name=app-prod-deploy \
#     --repo-owner=${var.github_owner} \
#     --repo-name=${var.github_repo} \
#     --branch-pattern="^main$" \
#     --build-config=cloudbuild.yaml \
#     --region=${var.region} \
#     --substitutions=_CLUSTER=app-prod-cluster,_REGION=${var.region},_REGISTRY=${var.region}-docker.pkg.dev/${var.project_id}/app-prod-app \
#     --project=${var.project_id}

# Cloud Scheduler — daily DB backup at 02:00 UTC
resource "google_cloud_scheduler_job" "db_backup" {
  name        = "${var.prefix}-${var.environment}-db-backup"
  description = "Daily Cloud SQL export to GCS"
  schedule    = "0 2 * * *"
  time_zone   = "UTC"
  region      = var.region
  project     = var.project_id

  http_target {
    http_method = "POST"
    uri         = "https://sqladmin.googleapis.com/sql/v1beta4/projects/${var.project_id}/instances/${module.cloud_sql.instance_name}/export"

    # GCS versioning on the backup bucket retains every daily overwrite for 90 days.
    # The fixed filename is intentional — versioning provides the retention history.
    # For named recovery points, use scripts/backup.sh which includes a timestamp.
    body = base64encode(jsonencode({
      exportContext = {
        kind      = "sql#exportContext"
        fileType  = "SQL"
        uri       = "gs://${module.cdn.backup_bucket_name}/sql-backups/${module.cloud_sql.instance_name}/daily/backup.sql.gz"
        databases = [var.db_name]
      }
    }))

    oauth_token {
      service_account_email = module.cloud_sql.backup_sa_email
    }

    headers = {
      "Content-Type" = "application/json"
    }
  }

  depends_on = [module.cloud_sql, module.cdn]
}
