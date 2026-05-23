output "cluster_name" {
  value = google_container_cluster.main.name
}

output "cluster_endpoint" {
  value     = google_container_cluster.main.endpoint
  sensitive = true
}

output "cluster_ca_certificate" {
  value     = google_container_cluster.main.master_auth[0].cluster_ca_certificate
  sensitive = true
}

output "web_workload_sa_email" {
  value = google_service_account.web_workload.email
}

output "api_workload_sa_email" {
  value = google_service_account.api_workload.email
}
