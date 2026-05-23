# Architecture — Node 3-Tier App on GKE

## Overview

A production-grade continuous delivery architecture for a Node.js 3-tier application hosted on Google Cloud Platform. All infrastructure is managed via Terraform, deployments are fully automated via GitLab CI, and the system is designed for zero-downtime updates, automatic failure recovery, and observability.

---

## Architecture Diagram

```
                           ┌─────────────────────────────────────────────┐
                           │              INTERNET (Users)                │
                           └──────────────┬──────────────────────────────┘
                                          │ HTTPS (443)
                           ┌─────────────▼──────────────────────────────┐
                           │         Google Cloud CDN                    │
                           │  (caches static assets globally)            │
                           └─────────────┬──────────────────────────────┘
                                          │
                           ┌─────────────▼──────────────────────────────┐
                           │  Global HTTP(S) Load Balancer               │
                           │  - Managed TLS certificates                 │
                           │  - HTTP → HTTPS redirect                    │
                           │  - URL routing (web / api / static)         │
                           └────┬──────────────────────┬────────────────┘
                                │                      │
                    ┌───────────▼──────┐   ┌──────────▼────────────┐
                    │   WEB TIER       │   │   API TIER            │
                    │ (GKE Deployment) │   │ (GKE Deployment)      │
                    │                  │   │                        │
                    │ min: 2 pods      │   │ min: 2 pods            │
                    │ max: 10 pods     │   │ max: 10 pods           │
                    │ HPA: CPU 60%     │   │ HPA: CPU 60%           │
                    │ Rolling updates  │   │ Rolling updates        │
                    │ PDB: min 1       │   │ PDB: min 1             │
                    │ CDN: enabled     │   │ CDN: disabled          │
                    └──────────────────┘   └──────────┬────────────┘
                                                       │ Private VPC
                                          ┌────────────▼───────────┐
                                          │   DB TIER               │
                                          │   Cloud SQL (Postgres)  │
                                          │                         │
                                          │ - HA (REGIONAL)         │
                                          │ - Private IP only       │
                                          │ - Automated backups     │
                                          │ - PITR enabled          │
                                          │ - NO public internet    │
                                          └─────────────────────────┘

────────────────────────── SUPPORTING SERVICES ──────────────────────────

  ┌─────────────────┐   ┌────────────────────┐   ┌──────────────────────┐
  │  GCS Buckets    │   │ Cloud Monitoring   │   │  Artifact Registry   │
  │                 │   │ + Cloud Logging    │   │  (Docker images)     │
  │ - static-assets │   │                    │   │                      │
  │ - backups       │   │ - Dashboards       │   │  web:sha / api:sha   │
  │ (90-day TTL)    │   │ - Alert policies   │   │                      │
  └─────────────────┘   │ - Uptime checks    │   └──────────────────────┘
                         └────────────────────┘

  ┌──────────────────────────────────────────────────────────────────────┐
  │  GitLab CI/CD Pipeline                                               │
  │                                                                      │
  │  main branch: test → build (web + api) → deploy to prod             │
  │  Auth: Workload Identity Federation (no stored keys)                 │
  └──────────────────────────────────────────────────────────────────────┘
```

---

## Tier Details

### Web Tier
- **Runtime**: Node.js / Express serving the frontend (or Nginx serving built SPA)
- **Deployment**: GKE `Deployment` in `prod` namespace
- **Scaling**: HPA (2–10 pods), CPU threshold 60%, multi-zone spread
- **CDN**: Cloud CDN enabled on the GKE backend service via `BackendConfig`
- **Resilience**: `maxUnavailable: 0` rolling update, `PodDisruptionBudget`, `preStop` drain hook
- **Security**: non-root, read-only filesystem, Workload Identity (no keys in pods)

### API Tier
- **Runtime**: Node.js / Express REST API
- **Deployment**: GKE `Deployment` in `prod` namespace, separate from web
- **Scaling**: HPA (2–10 pods), CPU threshold 60%, multi-zone spread
- **DB migrations**: Run as an `initContainer` before the main container starts — migrations are idempotent and run on every deployment
- **Secrets**: DB connection string injected from Kubernetes Secret, populated from GCP Secret Manager during CI deploy step
- **CDN**: Disabled — responses are dynamic

### DB Tier
- **Service**: Cloud SQL for PostgreSQL 15 (fully managed)
- **Availability**: `REGIONAL` mode = automatic failover, zero-downtime during instance maintenance
- **Access**: Private IP only (VPC peering via Private Service Access) — completely unreachable from the internet
- **Backups**: Automated daily backups at 02:00 UTC, 14-day retention, point-in-time recovery enabled
- **Extras**: Query Insights enabled, slow query logging (>1s), Cloud Scheduler exports to GCS for additional off-instance backups

---

## Network Architecture

```
VPC: 10.0.0.0/8
  └── GKE Subnet: 10.1.0.0/20
        ├── Pod CIDR:     10.2.0.0/16  (secondary range)
        └── Service CIDR: 10.3.0.0/20 (secondary range)

Private Service Access: Cloud SQL ↔ VPC peering
Cloud NAT: GKE private nodes → internet (for image pulls, API calls)
Firewall:
  - Internal: allow all 10.0.0.0/8
  - LB health checks: allow from 130.211.0.0/22, 35.191.0.0/16
  - No direct inbound to nodes or DB from internet
```

---

## CI/CD Pipeline (GitLab CI)

```
Trigger: push to main branch or tag

Stage 1 — test (parallel):
  ├── test:web  → npm lint + npm test (with coverage)
  └── test:api  → npm lint + npm test (with real Postgres service container)

Stage 2 — build (parallel, only on main/tag):
  ├── build:web → docker build → push to Artifact Registry (web:SHA, web:latest)
  └── build:api → docker build → push to Artifact Registry (api:SHA, api:latest)

Stage 3 — deploy (sequential, only on main):
  └── deploy:prod
        ├── kubectl apply base resources
        ├── Fetch DB credentials from Secret Manager → create k8s Secret
        ├── Apply BackendConfig (CDN config)
        ├── Apply Ingress + ManagedCertificates (domain-patched)
        ├── Apply Deployments (image-tag-patched)
        ├── Apply HPA + PDB
        ├── kubectl rollout status (waits for both to complete)
        └── health-check.sh (smoke test against live endpoints)

Auth: Workload Identity Federation — GitLab JWT → GCP short-lived token
      No service account keys stored anywhere.
```

---

## Zero-Downtime Deployments

| Mechanism | Purpose |
|---|---|
| `maxUnavailable: 0` | Never remove an old pod before a new one is Ready |
| `maxSurge: 1` | Creates one extra pod during rollout |
| `readinessProbe` | New pod only receives traffic once `/health` returns 200 |
| `preStop: sleep 5` | Gives load balancer time to drain connections before SIGTERM |
| `terminationGracePeriodSeconds` | Allows in-flight requests to complete |
| `PodDisruptionBudget` | Prevents node drain from removing the last replica |
| Topology spread | Pods spread across zones — zone failure loses ≤50% capacity |
| Cloud SQL REGIONAL | Database failover is automatic with no app changes needed |

---

## Failure Handling

| Failure | Response |
|---|---|
| Pod crash | Kubernetes restarts automatically; HPA maintains minimum replicas |
| Node failure | GKE replaces node (auto-repair); pods reschedule to healthy nodes |
| Zone outage | Multi-zone deployment — remaining zones absorb traffic |
| DB failover | Cloud SQL REGIONAL promotes standby automatically (< 60s) |
| Bad deployment | `kubectl rollout undo deployment/web -n prod` reverts instantly |
| Persistent traffic spike | HPA scales pods up; cluster autoscaler adds nodes |

---

## Logging

All logs are written to `stdout`/`stderr` and collected automatically by the GKE node agent into **Cloud Logging** (no log agents to manage on hosts).

- Container logs: `resource.type="k8s_container"`
- Audit logs: GCP Cloud Audit Logs (data access, admin activity)
- VPC flow logs: enabled on the GKE subnet
- Query logs: Cloud SQL slow query and connection logs → Cloud Logging

Query logs from Cloud Logging using Log Explorer:
```
resource.type="k8s_container"
resource.labels.cluster_name="app-prod-cluster"
resource.labels.namespace_name="prod"
```

---

## Metrics & Dashboards

**Cloud Monitoring dashboard** (`app-prod - Application Overview`):
- GKE pod CPU and memory utilization (by container)
- GKE pod restart count
- Cloud SQL CPU utilization
- HTTP 5xx error rate (log-based metric)

**Uptime checks**: `/health` on both web and api domains (60s interval)

**Alert policies**:
- Pod CrashLoopBackOff (restart rate > 3/min)
- Node CPU > 80% (sustained 5 min)
- Node Memory > 85% (sustained 5 min)
- Cloud SQL CPU > 80% (sustained 5 min)
- HTTP 5xx spike > 10/min

---

## Backups

| Layer | Mechanism | Retention |
|---|---|---|
| Cloud SQL automated | Built-in daily backup at 02:00 UTC | 14 snapshots |
| Cloud SQL PITR | Transaction log retention | 7 days |
| GCS export | Cloud Scheduler → `gcloud sql export` → GCS | 90 days |
| GCS versioning | Backup bucket has versioning enabled | Indefinite |

Manual restore: `./scripts/restore.sh --backup gs://BUCKET/path/backup.sql.gz --confirm`

---

## Security

- All GKE nodes are **private** (no public IPs)
- Cloud SQL is **private IP only** — no public endpoint
- Workload Identity: pods authenticate as GCP service accounts without keys
- Managed TLS certificates on the load balancer
- `readOnlyRootFilesystem: true` on all containers
- Non-root container users (UID 1000)
- Secrets stored in **Secret Manager**, not in git or environment variables
- GitLab CI uses **Workload Identity Federation** — no long-lived service account keys

---

## CDN Strategy

| Asset type | CDN layer | TTL |
|---|---|---|
| Static files (JS/CSS/images) | Cloud Storage + Cloud CDN backend bucket | 7 days (max), 1h (client) |
| Web tier responses | GKE BackendConfig Cloud CDN | 1 day default |
| API responses | No CDN (dynamic data) | — |

Cache invalidation: upload new assets with content-hashed filenames (handled by the frontend build toolchain).

---

## Infrastructure as Code

All GCP resources are managed by **Terraform** (`terraform/`):

```
terraform/
├── main.tf              # Root: providers + module wiring
├── variables.tf         # All configurable inputs
├── outputs.tf           # Key values (cluster name, bucket names, etc.)
├── backend.tf           # GCS remote state
└── modules/
    ├── vpc/             # VPC, subnets, Cloud NAT, PSA for Cloud SQL
    ├── gke/             # GKE cluster, node pools, Workload Identity bindings
    ├── cloud-sql/       # PostgreSQL HA instance, Secret Manager secrets
    ├── cdn/             # Cloud CDN, static assets bucket, backup bucket
    ├── artifact-registry/ # Docker registry, WIF pool for GitLab CI
    └── monitoring/      # Dashboards, alert policies, uptime checks
```

### Bootstrap steps

```bash
# 1. Create a GCS bucket for Terraform state (one-time, before terraform init)
gsutil mb -p YOUR_PROJECT_ID gs://YOUR_TF_STATE_BUCKET

# 2. Update terraform/backend.tf with bucket name
# 3. Copy and fill in your tfvars
cp terraform/terraform.tfvars.example terraform/terraform.tfvars

# 4. Initialise and apply
cd terraform
terraform init
terraform plan -out=tfplan
terraform apply tfplan

# 5. Configure kubectl
gcloud container clusters get-credentials app-prod-cluster \
  --region us-central1 --project YOUR_PROJECT_ID

# 6. Apply Kubernetes base resources
kubectl apply -f k8s/base/

# 7. Set GitLab CI/CD variables (see below)
```

### GitLab CI variables to set

| Variable | Value | Protected |
|---|---|---|
| `GCP_PROJECT_ID` | Your GCP project ID | Yes |
| `GCP_WIF_PROVIDER` | WIF provider resource name (from `terraform output`) | Yes |
| `GCP_CI_SA_EMAIL` | CI service account email (from `terraform output`) | Yes |
| `WEB_DOMAIN` | e.g. `app.example.com` | No |
| `API_DOMAIN` | e.g. `api.example.com` | No |
| `WEB_WORKLOAD_SA_EMAIL` | Web workload SA (from `terraform output`) | Yes |
| `API_WORKLOAD_SA_EMAIL` | API workload SA (from `terraform output`) | Yes |

---

## Operational Runbook

```bash
# View live logs for API tier
gcloud logging read \
  'resource.type="k8s_container" resource.labels.container_name="api"' \
  --project=YOUR_PROJECT --limit=100 --format=json | jq '.[] | .textPayload'

# Scale web tier manually
./scripts/scale.sh pods --tier web --replicas 5

# Scale node pool
./scripts/scale.sh nodes --min 2 --max 10

# Trigger manual rolling deploy
./scripts/rolling-deploy.sh --tag v1.2.3 --tier all

# Run manual database backup
GCP_PROJECT_ID=your-project ./scripts/backup.sh

# Restore from backup
./scripts/restore.sh \
  --backup gs://app-prod-backups-123456/sql-backups/app-prod-postgres-ab12/20240115-020000.sql.gz \
  --confirm

# Roll back a bad deployment
kubectl rollout undo deployment/web -n prod
kubectl rollout undo deployment/api -n prod

# Check rollout history
kubectl rollout history deployment/web -n prod
```
