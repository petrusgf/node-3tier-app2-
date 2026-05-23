output "instance_name" {
  value = google_sql_database_instance.main.name
}

output "private_ip" {
  value     = google_sql_database_instance.main.private_ip_address
  sensitive = true
}

output "db_name" {
  value = google_sql_database.app.name
}

output "password_secret_name" {
  value = google_secret_manager_secret.db_password.secret_id
}

output "connection_string_secret_name" {
  value = google_secret_manager_secret.db_connection_string.secret_id
}

output "backup_sa_email" {
  value = google_service_account.backup_sa.email
}
