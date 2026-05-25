resource "google_service_account" "gke_nodes" {
  account_id   = "${var.prefix}-gke-nodes"
  display_name = "GKE Node SA"
  project      = var.project_id
}

locals {
  node_sa_roles = [
    "roles/container.defaultNodeServiceAccount",
    "roles/artifactregistry.reader",
  ]
}

resource "google_project_iam_member" "node_sa_roles" {
  for_each = toset(local.node_sa_roles)

  project = var.project_id
  role    = each.value
  member  = "serviceAccount:${google_service_account.gke_nodes.email}"
}

locals {
  cluster_location = var.location != "" ? var.location : var.region
}

resource "google_container_cluster" "main" {
  name     = "${var.prefix}-cluster"
  location = local.cluster_location
  project  = var.project_id

  deletion_protection      = false
  remove_default_node_pool = true
  initial_node_count       = 1

  node_config {
    disk_type    = "pd-standard"
    disk_size_gb = 30
    machine_type = "e2-medium"
  }

  network    = var.network_id
  subnetwork = var.subnetwork_id

  # Regional private cluster — nodes have no public IPs
  private_cluster_config {
    enable_private_nodes    = true
    enable_private_endpoint = false
    master_ipv4_cidr_block  = "172.16.0.0/28"
  }

  master_authorized_networks_config {
    # Cloud Build uses dynamic Google IPs — restrict to your corp/VPN CIDR in production
    # by overriding var.master_authorized_cidr
    cidr_blocks {
      cidr_block   = var.master_authorized_cidr
      display_name = "authorized-access"
    }
  }

  ip_allocation_policy {
    cluster_secondary_range_name  = "gke-pods"
    services_secondary_range_name = "gke-services"
  }

  workload_identity_config {
    workload_pool = "${var.project_id}.svc.id.goog"
  }

  addons_config {
    http_load_balancing {
      disabled = false
    }
    horizontal_pod_autoscaling {
      disabled = false
    }
    gce_persistent_disk_csi_driver_config {
      enabled = true
    }
  }

  logging_service    = "logging.googleapis.com/kubernetes"
  monitoring_service = "monitoring.googleapis.com/kubernetes"

  release_channel {
    channel = "REGULAR"
  }

  network_policy {
    enabled  = true
    provider = "CALICO"
  }

  resource_labels = {
    environment = var.prefix
    managed-by  = "terraform"
  }

  lifecycle {
    ignore_changes = [initial_node_count]
  }
}

# System node pool — cluster infrastructure components only
resource "google_container_node_pool" "system" {
  name     = "${var.prefix}-system-pool"
  location = local.cluster_location
  cluster  = google_container_cluster.main.name
  project  = var.project_id

  initial_node_count = 1

  autoscaling {
    min_node_count = 1
    max_node_count = 2
  }

  management {
    auto_repair  = true
    auto_upgrade = true
  }

  node_config {
    machine_type = "e2-standard-2"
    disk_size_gb = 50
    disk_type    = "pd-standard"

    service_account = google_service_account.gke_nodes.email
    oauth_scopes    = ["https://www.googleapis.com/auth/cloud-platform"]

    workload_metadata_config {
      mode = "GKE_METADATA"
    }

    taint {
      key    = "node-role"
      value  = "system"
      effect = "NO_SCHEDULE"
    }

    labels = {
      "node-role" = "system"
    }

    shielded_instance_config {
      enable_secure_boot          = true
      enable_integrity_monitoring = true
    }
  }
}

# Application node pool — web and api workloads
resource "google_container_node_pool" "apps" {
  name     = "${var.prefix}-apps-pool"
  location = local.cluster_location
  cluster  = google_container_cluster.main.name
  project  = var.project_id

  initial_node_count = var.min_node_count

  autoscaling {
    min_node_count = var.min_node_count
    max_node_count = var.max_node_count
  }

  management {
    auto_repair  = true
    auto_upgrade = true
  }

  upgrade_settings {
    max_surge       = 1
    max_unavailable = 0
  }

  node_config {
    machine_type = var.machine_type
    disk_size_gb = 100
    disk_type    = "pd-standard"

    service_account = google_service_account.gke_nodes.email
    oauth_scopes    = ["https://www.googleapis.com/auth/cloud-platform"]

    workload_metadata_config {
      mode = "GKE_METADATA"
    }

    labels = {
      "node-role" = "apps"
    }

    shielded_instance_config {
      enable_secure_boot          = true
      enable_integrity_monitoring = true
    }
  }
}

# Wait for Workload Identity pool to propagate after cluster creation
resource "time_sleep" "wait_for_wi_pool" {
  depends_on      = [google_container_cluster.main]
  create_duration = "60s"
}

# Workload Identity binding for web tier
resource "google_service_account" "web_workload" {
  account_id   = "${var.prefix}-web"
  display_name = "Web tier workload SA"
  project      = var.project_id
}

resource "google_service_account_iam_member" "web_workload_identity" {
  service_account_id = google_service_account.web_workload.name
  role               = "roles/iam.workloadIdentityUser"
  member             = "serviceAccount:${var.project_id}.svc.id.goog[prod/web]"
  depends_on         = [time_sleep.wait_for_wi_pool]
}

# Workload Identity binding for api tier
resource "google_service_account" "api_workload" {
  account_id   = "${var.prefix}-api"
  display_name = "API tier workload SA"
  project      = var.project_id
}

resource "google_service_account_iam_member" "api_workload_identity" {
  service_account_id = google_service_account.api_workload.name
  role               = "roles/iam.workloadIdentityUser"
  member             = "serviceAccount:${var.project_id}.svc.id.goog[prod/api]"
  depends_on         = [time_sleep.wait_for_wi_pool]
}

# Allow api workload SA to access Secret Manager
resource "google_project_iam_member" "api_secret_accessor" {
  project = var.project_id
  role    = "roles/secretmanager.secretAccessor"
  member  = "serviceAccount:${google_service_account.api_workload.email}"
}
