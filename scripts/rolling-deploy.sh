#!/usr/bin/env bash
# Manually trigger a rolling deployment for web and/or api.
# Usage: ./scripts/rolling-deploy.sh --tag v1.2.3 [--tier web|api|all]

set -euo pipefail

PROJECT_ID="${GCP_PROJECT_ID:-$(gcloud config get-value project)}"
CLUSTER_LOCATION="${CLUSTER_LOCATION:-us-central1}"
CLUSTER_NAME="${CLUSTER_NAME:-app-prod-cluster}"
REGISTRY="${GCP_REGION}-docker.pkg.dev/${PROJECT_ID}/app-prod-app"
NAMESPACE="prod"
TAG=""
TIER="all"

while [[ $# -gt 0 ]]; do
  case $1 in
    --tag)  TAG="$2"; shift 2 ;;
    --tier) TIER="$2"; shift 2 ;;
    *) echo "Unknown option: $1"; exit 1 ;;
  esac
done

[[ -n "${TAG}" ]] || { echo "Usage: rolling-deploy.sh --tag <image-tag> [--tier web|api|all]"; exit 1; }

gcloud container clusters get-credentials "${CLUSTER_NAME}" \
  --location "${CLUSTER_LOCATION}" --project "${PROJECT_ID}"

deploy_tier() {
  local tier="$1"
  local image="${REGISTRY}/${tier}:${TAG}"
  echo "[$(date -u)] Updating ${tier} to image tag ${TAG}..."
  kubectl set image "deployment/${tier}" "${tier}=${image}" -n "${NAMESPACE}"
  kubectl rollout status "deployment/${tier}" -n "${NAMESPACE}" --timeout=300s
  echo "[$(date -u)] ${tier} deployment complete."
}

case "${TIER}" in
  web)  deploy_tier web ;;
  api)  deploy_tier api ;;
  all)
    deploy_tier web &
    deploy_tier api &
    wait
    ;;
  *)
    echo "Invalid tier: ${TIER}. Use web, api, or all."
    exit 1
    ;;
esac

echo "[$(date -u)] Rollout finished. Running health checks..."
scripts/health-check.sh
