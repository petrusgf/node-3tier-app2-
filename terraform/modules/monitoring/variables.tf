variable "project_id" { type = string }
variable "region" { type = string }
variable "prefix" { type = string }
variable "cluster_name" { type = string }
variable "sql_instance_name" { type = string }
variable "alert_notification_email" { type = string }

variable "web_domain" {
  type    = string
  default = ""
}

variable "api_domain" {
  type    = string
  default = ""
}
