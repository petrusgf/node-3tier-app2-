variable "project_id" { type = string }
variable "region" { type = string }
variable "prefix" { type = string }
variable "network_id" { type = string }
variable "private_vpc_connection" {}
variable "db_tier" { type = string }
variable "db_name" { type = string }
variable "db_user" { type = string }
variable "backup_bucket_name" { type = string }

variable "db_availability_type" {
  description = "REGIONAL for HA (prod) or ZONAL for cost savings (demo)"
  type        = string
  default     = "REGIONAL"
}
