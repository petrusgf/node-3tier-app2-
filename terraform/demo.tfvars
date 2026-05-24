project_id               = "project-34aff184-c47b-48c0-a92"
region                   = "us-central1"
environment              = "prod"
prefix                   = "app"
web_domain               = "web.aiforu2.com"
api_domain               = "api.aiforu2.com"
alert_notification_email = "toptalinterviewps@gmail.com"
github_owner             = "petrusgf"
github_repo              = "node-3tier-app2"
backup_bucket_location   = "US"

# Cost-optimised for demo (~$38/week vs ~$169/week for prod)
gke_location         = "us-central1-a"   # zonal → 1 node instead of 3
gke_machine_type     = "e2-standard-2"   # 2 vCPU / 8 GB instead of 4 vCPU
gke_min_node_count   = 1
gke_max_node_count   = 3
db_tier              = "db-g1-small"     # 1 vCPU / 1.7 GB
db_availability_type = "ZONAL"           # no standby replica
db_name              = "appdb"
db_user              = "appuser"
