output "network_id" {
  value = google_compute_network.main.id
}

output "network_name" {
  value = google_compute_network.main.name
}

output "gke_subnetwork_id" {
  value = google_compute_subnetwork.gke.id
}

output "gke_subnetwork_name" {
  value = google_compute_subnetwork.gke.name
}

output "private_vpc_connection" {
  value = google_service_networking_connection.private_vpc_connection
}
