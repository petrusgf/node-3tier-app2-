# Static assets bucket — served via Cloud CDN
resource "google_storage_bucket" "static_assets" {
  name                        = "${var.prefix}-static-assets"
  location                    = var.backup_bucket_location
  project                     = var.project_id
  uniform_bucket_level_access = true
  force_destroy               = false

  website {
    main_page_suffix = "index.html"
    not_found_page   = "404.html"
  }

  cors {
    origin          = ["https://${var.web_domain}"]
    method          = ["GET", "HEAD"]
    response_header = ["Content-Type", "Cache-Control"]
    max_age_seconds = 3600
  }

  lifecycle_rule {
    action {
      type = "Delete"
    }
    condition {
      age = 365
    }
  }

  labels = {
    environment = var.prefix
    managed-by  = "terraform"
    purpose     = "static-assets"
  }
}

# Make static assets publicly readable
resource "google_storage_bucket_iam_member" "static_assets_public" {
  bucket = google_storage_bucket.static_assets.name
  role   = "roles/storage.objectViewer"
  member = "allUsers"
}

# Backup bucket — NOT public
resource "google_storage_bucket" "backups" {
  name                        = "${var.prefix}-backups-${data.google_project.current.number}"
  location                    = var.backup_bucket_location
  project                     = var.project_id
  uniform_bucket_level_access = true
  force_destroy               = false

  lifecycle_rule {
    action {
      type = "Delete"
    }
    condition {
      age = 90
    }
  }

  versioning {
    enabled = true
  }

  labels = {
    environment = var.prefix
    managed-by  = "terraform"
    purpose     = "backups"
  }
}

data "google_project" "current" {
  project_id = var.project_id
}

# Global static IP — used by the GKE Ingress load balancer (CDN enabled via BackendConfig)
resource "google_compute_global_address" "web_ip" {
  name    = "${var.prefix}-web-ip"
  project = var.project_id
}
