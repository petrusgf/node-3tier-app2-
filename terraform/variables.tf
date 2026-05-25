variable "project_id" {
  description = "GCP project ID"
  type        = string
}

variable "region" {
  description = "GCP region"
  type        = string
  default     = "us-central1"
}

variable "environment" {
  description = "Environment name (prod, staging)"
  type        = string
  default     = "prod"
}

variable "prefix" {
  description = "Resource name prefix"
  type        = string
  default     = "app"
}

variable "web_domain" {
  description = "Domain for the web tier (e.g. app.example.com)"
  type        = string
}

variable "api_domain" {
  description = "Domain for the API tier (e.g. api.example.com)"
  type        = string
}

variable "gke_machine_type" {
  description = "GKE node machine type"
  type        = string
  default     = "e2-standard-4"
}

variable "gke_min_node_count" {
  description = "Minimum nodes per zone in the app node pool"
  type        = number
  default     = 1
}

variable "gke_max_node_count" {
  description = "Maximum nodes per zone in the app node pool"
  type        = number
  default     = 5
}

variable "db_tier" {
  description = "Cloud SQL instance tier"
  type        = string
  default     = "db-custom-2-7680"
}

variable "db_name" {
  description = "Database name"
  type        = string
  default     = "appdb"
}

variable "db_user" {
  description = "Database user"
  type        = string
  default     = "appuser"
}

variable "backup_bucket_location" {
  description = "Location for the GCS backup bucket"
  type        = string
  default     = "US"
}

variable "alert_notification_email" {
  description = "Email address for monitoring alerts"
  type        = string
}

variable "gke_location" {
  description = "GKE cluster location. Use a region (e.g. us-central1) for HA or a zone (e.g. us-central1-a) to save cost"
  type        = string
  default     = ""
}

variable "db_availability_type" {
  description = "Cloud SQL availability: REGIONAL (HA, prod) or ZONAL (cheaper, demo)"
  type        = string
  default     = "REGIONAL"
}

variable "github_owner" {
  description = "GitHub username or org that owns the repo"
  type        = string
}

variable "github_repo" {
  description = "GitHub repository name"
  type        = string
  default     = "node-3tier-app2"
}
