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

# Global static IP for the HTTPS load balancer
resource "google_compute_global_address" "web_ip" {
  name    = "${var.prefix}-web-ip"
  project = var.project_id
}

# Backend bucket for static assets with CDN enabled
resource "google_compute_backend_bucket" "static_assets" {
  name        = "${var.prefix}-static-backend"
  bucket_name = google_storage_bucket.static_assets.name
  enable_cdn  = true
  project     = var.project_id

  cdn_policy {
    cache_mode        = "CACHE_ALL_STATIC"
    default_ttl       = 86400
    max_ttl           = 604800
    client_ttl        = 3600
    serve_while_stale = 86400
  }
}

# Managed SSL certificates
resource "google_compute_managed_ssl_certificate" "web" {
  name    = "${var.prefix}-web-cert"
  project = var.project_id

  managed {
    domains = [var.web_domain]
  }
}

resource "google_compute_managed_ssl_certificate" "api" {
  name    = "${var.prefix}-api-cert"
  project = var.project_id

  managed {
    domains = [var.api_domain]
  }
}

# URL map — GKE NEG backends are added after GKE Ingress creates them
# This map handles the /static/* path → CDN bucket
resource "google_compute_url_map" "static" {
  name            = "${var.prefix}-static-url-map"
  project         = var.project_id
  default_service = google_compute_backend_bucket.static_assets.id

  host_rule {
    hosts        = [var.web_domain]
    path_matcher = "static-paths"
  }

  path_matcher {
    name            = "static-paths"
    default_service = google_compute_backend_bucket.static_assets.id
  }
}

# HTTPS proxy for static assets
resource "google_compute_target_https_proxy" "static" {
  name             = "${var.prefix}-static-https-proxy"
  project          = var.project_id
  url_map          = google_compute_url_map.static.id
  ssl_certificates = [google_compute_managed_ssl_certificate.web.id]
}

# Forwarding rule for static CDN
resource "google_compute_global_forwarding_rule" "static_https" {
  name                  = "${var.prefix}-static-https"
  project               = var.project_id
  ip_protocol           = "TCP"
  load_balancing_scheme = "EXTERNAL"
  port_range            = "443"
  target                = google_compute_target_https_proxy.static.id
  ip_address            = google_compute_global_address.web_ip.id
}

# HTTP → HTTPS redirect
resource "google_compute_url_map" "https_redirect" {
  name    = "${var.prefix}-https-redirect"
  project = var.project_id

  default_url_redirect {
    https_redirect         = true
    redirect_response_code = "MOVED_PERMANENTLY_DEFAULT"
    strip_query            = false
  }
}

resource "google_compute_target_http_proxy" "redirect" {
  name    = "${var.prefix}-http-redirect"
  project = var.project_id
  url_map = google_compute_url_map.https_redirect.id
}

resource "google_compute_global_forwarding_rule" "http_redirect" {
  name                  = "${var.prefix}-http-redirect"
  project               = var.project_id
  ip_protocol           = "TCP"
  load_balancing_scheme = "EXTERNAL"
  port_range            = "80"
  target                = google_compute_target_http_proxy.redirect.id
  ip_address            = google_compute_global_address.web_ip.id
}
