#!/usr/bin/env bash
# Scale web or api deployments, or resize GKE node pool.
# Usage:
#   ./scripts/scale.sh pods --tier web --replicas 5
#   ./scripts/scale.sh pods --tier api --replicas 3
#   ./scripts/scale.sh nodes --min 2 --max 8
#   ./scripts/scale.sh nodes --min 1 --max 5

set -euo pipefail

PROJECT_ID="${GCP_PROJECT_ID:-$(gcloud config get-value project)}"
REGION="${GCP_REGION:-us-central1}"
CLUSTER_NAME="${CLUSTER_NAME:-app-prod-cluster}"
NAMESPACE="prod"

command="$1"; shift

case "${command}" in

  pods)
    TIER=""
    REPLICAS=""
    while [[ $# -gt 0 ]]; do
      case $1 in
        --tier)     TIER="$2"; shift 2 ;;
        --replicas) REPLICAS="$2"; shift 2 ;;
        *) echo "Unknown option: $1"; exit 1 ;;
      esac
    done
    [[ -n "${TIER}" && -n "${REPLICAS}" ]] || { echo "Usage: scale.sh pods --tier <web|api> --replicas N"; exit 1; }
    gcloud container clusters get-credentials "${CLUSTER_NAME}" \
      --region "${REGION}" --project "${PROJECT_ID}" 2>/dev/null
    echo "Scaling ${TIER} to ${REPLICAS} replicas..."
    kubectl scale deployment/"${TIER}" --replicas="${REPLICAS}" -n "${NAMESPACE}"
    kubectl rollout status deployment/"${TIER}" -n "${NAMESPACE}" --timeout=120s
    echo "Done. Current pods:"
    kubectl get pods -n "${NAMESPACE}" -l "app=${TIER}"
    ;;

  nodes)
    MIN_COUNT=""
    MAX_COUNT=""
    POOL_NAME="app-prod-apps-pool"
    while [[ $# -gt 0 ]]; do
      case $1 in
        --min)  MIN_COUNT="$2"; shift 2 ;;
        --max)  MAX_COUNT="$2"; shift 2 ;;
        --pool) POOL_NAME="$2"; shift 2 ;;
        *) echo "Unknown option: $1"; exit 1 ;;
      esac
    done
    [[ -n "${MIN_COUNT}" && -n "${MAX_COUNT}" ]] || { echo "Usage: scale.sh nodes --min N --max N"; exit 1; }
    echo "Updating node pool autoscaling: min=${MIN_COUNT} max=${MAX_COUNT}..."
    gcloud container clusters update "${CLUSTER_NAME}" \
      --enable-autoscaling \
      --node-pool="${POOL_NAME}" \
      --min-nodes="${MIN_COUNT}" \
      --max-nodes="${MAX_COUNT}" \
      --region="${REGION}" \
      --project="${PROJECT_ID}"
    echo "Done."
    ;;

  *)
    echo "Usage: scale.sh <pods|nodes> [options]"
    exit 1
    ;;
esac
