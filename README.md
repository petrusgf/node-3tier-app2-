# Node.js 3-Tier App — Production CD Architecture on GCP

A production-grade continuous delivery architecture for a 3-tier Node.js application on Google Cloud Platform.

## Presentation

[Architecture & CD Pipeline Presentation](https://docs.google.com/presentation/d/1GpaMESeEIsecx6zIrWt2E6q61vp5BZefMK73_a-DYPE/edit?usp=sharing)

## Stack

- **Runtime**: GKE (regional, us-central1) — web + api tiers
- **Database**: Cloud SQL PostgreSQL 15 (REGIONAL HA)
- **CI/CD**: Google Cloud Build — triggered on push to `main`
- **IaC**: Terraform (6 modules) — VPC, GKE, Cloud SQL, CDN, Artifact Registry, Monitoring
- **Registry**: Artifact Registry
- **Security**: Workload Identity, NetworkPolicy (Calico), Secret Manager
- **Observability**: Cloud Monitoring dashboards + alert policies + uptime checks

## Structure

```
├── api/              # Node.js API tier
├── web/              # Node.js Web tier
├── docker/           # Dockerfiles
├── k8s/              # Kubernetes manifests
├── scripts/          # Operational scripts (start, stop, scale, backup, restore)
├── terraform/        # Infrastructure as Code
└── cloudbuild.yaml   # CD pipeline
```

## Scripts

```bash
# Start / Stop
GCP_PROJECT_ID=<project> ./scripts/stop.sh
GCP_PROJECT_ID=<project> ./scripts/start.sh

# Scale
./scripts/scale.sh pods --tier web --replicas 5
./scripts/scale.sh nodes --min 2 --max 8

# Manual deploy
./scripts/rolling-deploy.sh --tag <commit-sha> --tier all

# Backup / Restore
./scripts/backup.sh
./scripts/restore.sh --backup gs://<bucket>/path/to/backup.sql.gz
```
