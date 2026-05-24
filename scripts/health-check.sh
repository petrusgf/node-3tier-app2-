#!/usr/bin/env bash
# Post-deployment health check — verifies both tiers respond correctly.
# Called from Cloud Build after kubectl rollout status.

set -euo pipefail

WEB_URL="${WEB_URL:-https://${WEB_DOMAIN:-localhost}}"
API_URL="${API_URL:-https://${API_DOMAIN:-localhost}}"
MAX_RETRIES=10
RETRY_DELAY=15

check_endpoint() {
  local name="$1"
  local url="$2"
  local expected_status="${3:-200}"

  echo "[check] ${name} → ${url}"
  for i in $(seq 1 "${MAX_RETRIES}"); do
    status=$(curl -sSo /dev/null -w "%{http_code}" --max-time 10 "${url}" || echo "000")
    if [[ "${status}" == "${expected_status}" ]]; then
      echo "  ✓ ${name} returned HTTP ${status}"
      return 0
    fi
    echo "  attempt ${i}/${MAX_RETRIES}: got HTTP ${status}, retrying in ${RETRY_DELAY}s..."
    sleep "${RETRY_DELAY}"
  done

  echo "  ✗ ${name} health check FAILED after ${MAX_RETRIES} attempts (last status: ${status})"
  return 1
}

echo "=== Post-deployment health checks ==="
FAILED=0

check_endpoint "Web health"   "${WEB_URL}/health" 200 || FAILED=1
check_endpoint "API health"   "${API_URL}/health" 200 || FAILED=1

if [[ ${FAILED} -eq 0 ]]; then
  echo ""
  echo "=== All health checks passed ==="
else
  echo ""
  echo "=== HEALTH CHECKS FAILED (pods are running — LB may still be provisioning) ==="
  if command -v kubectl &>/dev/null; then
    echo "--- Web pod status ---"
    kubectl get pods -n prod -l app=web
    echo "--- API pod status ---"
    kubectl get pods -n prod -l app=api
  fi
  echo "NOTE: On first deploy, GKE load balancer can take 10-15 min to provision."
  echo "      Verify manually: curl https://web.aiforu2.com/health"
  exit 1
fi
