#!/usr/bin/env bash
# Gracefully bring the application stack offline.
# Scales GKE deployments to zero and stops the Cloud SQL instance.
# Usage: GCP_PROJECT_ID=your-project ./scripts/stop.sh [--skip-db]

set -euo pipefail

PROJECT_ID="${GCP_PROJECT_ID:-$(gcloud config get-value project)}"
REGION="${GCP_REGION:-us-central1}"
CLUSTER_LOCATION="${CLUSTER_LOCATION:-us-central1}"
CLUSTER_NAME="${CLUSTER_NAME:-app-prod-cluster}"
SQL_INSTANCE="${SQL_INSTANCE:-}"
NAMESPACE="prod"
SKIP_DB=false

while [[ $# -gt 0 ]]; do
  case $1 in
    --skip-db) SKIP_DB=true; shift ;;
    *) echo "Unknown option: $1"; exit 1 ;;
  esac
done

echo "=== Stopping application stack (project: ${PROJECT_ID}) ==="

# ── 1. Get GKE credentials ───────────────────────────────────────────────────
echo "[gke] Fetching cluster credentials..."
gcloud container clusters get-credentials "${CLUSTER_NAME}" \
  --location "${CLUSTER_LOCATION}" --project "${PROJECT_ID}"

# ── 2. Scale deployments to zero ────────────────────────────────────────────
echo "[web] Scaling web deployment to 0 replicas..."
kubectl scale deployment/web --replicas=0 -n "${NAMESPACE}"

echo "[api] Scaling api deployment to 0 replicas..."
kubectl scale deployment/api --replicas=0 -n "${NAMESPACE}"

echo "[gke] Waiting for pods to terminate..."
kubectl wait --for=delete pod -l "app in (web,api)" \
  -n "${NAMESPACE}" --timeout=120s 2>/dev/null || true

echo "[gke] Current pods:"
kubectl get pods -n "${NAMESPACE}"

# ── 3. Stop Cloud SQL instance (optional) ───────────────────────────────────
if [[ "${SKIP_DB}" == "true" ]]; then
  echo "[db] Skipping Cloud SQL stop (--skip-db flag set)."
else
  if [[ -z "${SQL_INSTANCE}" ]]; then
    SQL_INSTANCE=$(gcloud sql instances list \
      --project="${PROJECT_ID}" \
      --filter="name~'^app-prod-postgres'" \
      --format="value(name)" | head -1)
  fi

  if [[ -z "${SQL_INSTANCE}" ]]; then
    echo "WARNING: Could not find Cloud SQL instance. Skipping DB stop."
  else
    echo "[db] Stopping Cloud SQL instance '${SQL_INSTANCE}'..."
    gcloud sql instances patch "${SQL_INSTANCE}" \
      --activation-policy=NEVER \
      --project="${PROJECT_ID}"
    echo "[db] Cloud SQL instance set to NEVER (stopped)."
  fi
fi

echo ""
echo "=== Application stack is DOWN ==="
echo "    To restart: GCP_PROJECT_ID=${PROJECT_ID} ./scripts/start.sh"
