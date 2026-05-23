#!/usr/bin/env bash
# Restore a Cloud SQL database from a GCS export.
# Usage: ./scripts/restore.sh --backup gs://BUCKET/path/to/backup.sql.gz
#                             [--instance INSTANCE_NAME]
#                             [--db DATABASE_NAME]
#                             [--confirm]

set -euo pipefail

PROJECT_ID="${GCP_PROJECT_ID:-$(gcloud config get-value project)}"
INSTANCE_NAME="${SQL_INSTANCE:-}"
DB_NAME="${DB_NAME:-appdb}"
BACKUP_URI=""
CONFIRM=false

while [[ $# -gt 0 ]]; do
  case $1 in
    --backup)   BACKUP_URI="$2"; shift 2 ;;
    --instance) INSTANCE_NAME="$2"; shift 2 ;;
    --db)       DB_NAME="$2"; shift 2 ;;
    --confirm)  CONFIRM=true; shift ;;
    *) echo "Unknown option: $1"; exit 1 ;;
  esac
done

if [[ -z "${BACKUP_URI}" ]]; then
  echo "ERROR: --backup <gcs-uri> is required"
  exit 1
fi

if [[ -z "${INSTANCE_NAME}" ]]; then
  INSTANCE_NAME=$(gcloud sql instances list \
    --project="${PROJECT_ID}" \
    --filter="name~app-prod" \
    --format="value(name)" | head -1)
fi

echo "================================================================"
echo "  WARNING: This will OVERWRITE the database '${DB_NAME}'"
echo "  Instance : ${INSTANCE_NAME}"
echo "  Source   : ${BACKUP_URI}"
echo "================================================================"

if [[ "${CONFIRM}" != "true" ]]; then
  read -rp "Type 'yes' to proceed: " answer
  [[ "${answer}" == "yes" ]] || { echo "Aborted."; exit 0; }
fi

echo "[$(date -u)] Starting import from ${BACKUP_URI}..."

gcloud sql import sql "${INSTANCE_NAME}" "${BACKUP_URI}" \
  --database="${DB_NAME}" \
  --project="${PROJECT_ID}"

echo "[$(date -u)] Restore complete."
