output "static_bucket_name" {
  value = google_storage_bucket.static_assets.name
}

output "backup_bucket_name" {
  value = google_storage_bucket.backups.name
}

output "web_ip_address" {
  value = google_compute_global_address.web_ip.address
}

output "static_backend_bucket_id" {
  value = google_compute_backend_bucket.static_assets.id
}

output "web_ssl_cert_id" {
  value = google_compute_managed_ssl_certificate.web.id
}

output "api_ssl_cert_id" {
  value = google_compute_managed_ssl_certificate.api.id
}
