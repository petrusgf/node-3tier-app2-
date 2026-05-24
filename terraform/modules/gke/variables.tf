variable "project_id" { type = string }
variable "region" { type = string }
variable "prefix" { type = string }
variable "network_id" { type = string }
variable "subnetwork_id" { type = string }
variable "machine_type" { type = string }
variable "min_node_count" { type = number }
variable "max_node_count" { type = number }
variable "registry_id" { type = string }

variable "location" {
  description = "Cluster location — a region for HA (prod) or a single zone for cost savings (demo)"
  type        = string
  default     = ""
}

variable "master_authorized_cidr" {
  description = "CIDR allowed to reach the GKE API server. Defaults to 0.0.0.0/0 for Cloud Build compatibility (Cloud Build IPs are dynamic). Restrict to your corp/VPN CIDR in production."
  type        = string
  default     = "0.0.0.0/0"
}
