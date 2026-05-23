#!/usr/bin/env bash
# Manual or scheduled Cloud SQL export to GCS.
# Called by Cloud Scheduler; can also be run manually.
# Usage: ./scripts/backup.sh [--instance INSTANCE_NAME] [--bucket BUCKET_NAME]

set -euo pipefail

PROJECT_ID="${GCP_PROJECT_ID:-$(gcloud config get-value project)}"
REGION="${GCP_REGION:-us-central1}"
INSTANCE_NAME="${SQL_INSTANCE:-}"
BACKUP_BUCKET="${BACKUP_BUCKET:-}"
DB_NAME="${DB_NAME:-appdb}"
TIMESTAMP=$(date -u +"%Y%m%d-%H%M%S")

# Parse flags
while [[ $# -gt 0 ]]; do
  case $1 in
    --instance) INSTANCE_NAME="$2"; shift 2 ;;
    --bucket)   BACKUP_BUCKET="$2"; shift 2 ;;
    --db)       DB_NAME="$2"; shift 2 ;;
    *) echo "Unknown option: $1"; exit 1 ;;
  esac
done

# Auto-detect instance and bucket if not provided
if [[ -z "${INSTANCE_NAME}" ]]; then
  INSTANCE_NAME=$(gcloud sql instances list \
    --project="${PROJECT_ID}" \
    --filter="name~app-prod" \
    --format="value(name)" | head -1)
fi

if [[ -z "${BACKUP_BUCKET}" ]]; then
  BACKUP_BUCKET=$(gcloud storage buckets list \
    --project="${PROJECT_ID}" \
    --filter="name~backups" \
    --format="value(name)" | head -1)
fi

if [[ -z "${INSTANCE_NAME}" || -z "${BACKUP_BUCKET}" ]]; then
  echo "ERROR: Could not detect SQL instance or backup bucket. Set SQL_INSTANCE and BACKUP_BUCKET."
  exit 1
fi

EXPORT_URI="gs://${BACKUP_BUCKET}/sql-backups/${INSTANCE_NAME}/${TIMESTAMP}.sql.gz"

echo "[$(date -u)] Starting Cloud SQL export"
echo "  Instance : ${INSTANCE_NAME}"
echo "  Bucket   : ${BACKUP_BUCKET}"
echo "  URI      : ${EXPORT_URI}"

gcloud sql export sql "${INSTANCE_NAME}" "${EXPORT_URI}" \
  --database="${DB_NAME}" \
  --project="${PROJECT_ID}" \
  --async

# Poll until operation completes
echo "[$(date -u)] Waiting for export operation..."
TIMEOUT=1800
ELAPSED=0
while ! gcloud sql operations list \
    --instance="${INSTANCE_NAME}" \
    --project="${PROJECT_ID}" \
    --filter="operationType=EXPORT AND status=DONE" \
    --format="value(name)" | grep -q .; do
  sleep 15
  ELAPSED=$((ELAPSED + 15))
  if [[ ${ELAPSED} -ge ${TIMEOUT} ]]; then
    echo "ERROR: Export timed out after ${TIMEOUT}s"
    exit 1
  fi
done

echo "[$(date -u)] Export complete: ${EXPORT_URI}"

# Delete backups older than 90 days
echo "[$(date -u)] Pruning backups older than 90 days..."
CUTOFF=$(date -u -d "90 days ago" +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null || \
         date -u -v-90d +"%Y-%m-%dT%H:%M:%SZ")

gcloud storage objects list "gs://${BACKUP_BUCKET}/sql-backups/${INSTANCE_NAME}/" \
  --format="value(name,timeCreated)" | \
  while read -r name created; do
    if [[ "${created}" < "${CUTOFF}" ]]; then
      echo "  Deleting old backup: ${name}"
      gcloud storage rm "gs://${BACKUP_BUCKET}/${name}" || true
    fi
  done

echo "[$(date -u)] Backup job complete."
