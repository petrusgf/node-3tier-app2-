output "static_bucket_name" {
  value = google_storage_bucket.static_assets.name
}

output "backup_bucket_name" {
  value = google_storage_bucket.backups.name
}

output "web_ip_address" {
  value = google_compute_global_address.web_ip.address
}
