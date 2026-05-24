#!/usr/bin/env bash
# Bring the full application stack online.
# Starts Cloud SQL instance and scales GKE deployments to minimum replicas.
# Usage: GCP_PROJECT_ID=your-project ./scripts/start.sh

set -euo pipefail

PROJECT_ID="${GCP_PROJECT_ID:-$(gcloud config get-value project)}"
REGION="${GCP_REGION:-us-central1}"
CLUSTER_LOCATION="${CLUSTER_LOCATION:-us-central1-a}"
CLUSTER_NAME="${CLUSTER_NAME:-app-prod-cluster}"
SQL_INSTANCE="${SQL_INSTANCE:-}"
NAMESPACE="prod"
WEB_MIN_REPLICAS=2
API_MIN_REPLICAS=2

echo "=== Starting application stack (project: ${PROJECT_ID}) ==="

# ── 1. Start Cloud SQL instance (if stopped) ────────────────────────────────
if [[ -z "${SQL_INSTANCE}" ]]; then
  SQL_INSTANCE=$(gcloud sql instances list \
    --project="${PROJECT_ID}" \
    --filter="name~'^app-prod-postgres'" \
    --format="value(name)" | head -1)
fi

if [[ -z "${SQL_INSTANCE}" ]]; then
  echo "WARNING: Could not find Cloud SQL instance. Skipping DB start."
else
  STATE=$(gcloud sql instances describe "${SQL_INSTANCE}" \
    --project="${PROJECT_ID}" --format="value(state)")
  if [[ "${STATE}" == "RUNNABLE" ]]; then
    echo "[db] Cloud SQL '${SQL_INSTANCE}' is already running."
  else
    echo "[db] Activating Cloud SQL instance '${SQL_INSTANCE}'..."
    gcloud sql instances patch "${SQL_INSTANCE}" \
      --activation-policy=ALWAYS \
      --project="${PROJECT_ID}"
    echo "[db] Waiting for Cloud SQL to be RUNNABLE..."
    for i in $(seq 1 20); do
      STATE=$(gcloud sql instances describe "${SQL_INSTANCE}" \
        --project="${PROJECT_ID}" --format="value(state)")
      [[ "${STATE}" == "RUNNABLE" ]] && break
      echo "  attempt ${i}/20: state=${STATE}, retrying in 10s..."
      sleep 10
    done
    echo "[db] Cloud SQL state: ${STATE}"
  fi
fi

# ── 2. Get GKE credentials ───────────────────────────────────────────────────
echo "[gke] Fetching cluster credentials..."
gcloud container clusters get-credentials "${CLUSTER_NAME}" \
  --location "${CLUSTER_LOCATION}" --project "${PROJECT_ID}"

# ── 3. Scale deployments up ──────────────────────────────────────────────────
echo "[web] Scaling web deployment to ${WEB_MIN_REPLICAS} replicas..."
kubectl scale deployment/web --replicas="${WEB_MIN_REPLICAS}" -n "${NAMESPACE}"

echo "[api] Scaling api deployment to ${API_MIN_REPLICAS} replicas..."
kubectl scale deployment/api --replicas="${API_MIN_REPLICAS}" -n "${NAMESPACE}"

# ── 4. Wait for rollout ──────────────────────────────────────────────────────
echo "[web] Waiting for rollout..."
kubectl rollout status deployment/web -n "${NAMESPACE}" --timeout=180s

echo "[api] Waiting for rollout..."
kubectl rollout status deployment/api -n "${NAMESPACE}" --timeout=180s

# ── 5. Summary ───────────────────────────────────────────────────────────────
echo ""
echo "=== Application stack is UP ==="
kubectl get pods -n "${NAMESPACE}"
