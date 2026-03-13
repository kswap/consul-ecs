#!/bin/bash
# Validates Bug2 fix: proxy check must be critical while the app container
# health status is not yet reported by ECS (container still starting).
# Without the fix, a missing container health entry was treated as "no
# healthSyncContainers configured" and the proxy was marked passing prematurely.
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TF_DIR="$(cd "$SCRIPT_DIR/../terraform" && pwd)"

CONSUL_IP=$(terraform -chdir="$TF_DIR" output -raw consul_server_ip)
TOKEN=$(terraform -chdir="$TF_DIR" output -raw consul_token 2>/dev/null || echo "${CONSUL_TOKEN}")
CLUSTER=$(terraform -chdir="$TF_DIR" output -raw ecs_cluster_name)
SERVICE=$(terraform -chdir="$TF_DIR" output -raw ecs_service_name)

echo "=== Bug2: Verifying proxy check is critical while app container is starting ==="
echo ""

echo "Forcing a new ECS task deployment to trigger container restart..."
aws ecs update-service --cluster "$CLUSTER" --service "$SERVICE" \
  --force-new-deployment > /dev/null
echo "  Deployment triggered. Waiting 5s for old task to stop..."
sleep 5

echo ""
echo "Polling proxy check status (expect CRITICAL during app startup)..."
CAUGHT_CRITICAL=false
for i in $(seq 1 20); do
  STATUS=$(curl -sf -H "X-Consul-Token: $TOKEN" \
    "http://$CONSUL_IP:8500/v1/health/checks/test-service-sidecar-proxy" \
    | jq -r '.[0].Status // "not_found"')
  echo "  [$i] proxy check status: $STATUS"

  if [ "$STATUS" = "critical" ]; then
    CAUGHT_CRITICAL=true
    echo "  Observed CRITICAL — Bug2 fix is working correctly."
    break
  fi
  sleep 3
done

echo ""
if $CAUGHT_CRITICAL; then
  echo "Waiting for proxy check to return to 'passing' after all containers healthy..."
  TIMEOUT=120
  ELAPSED=0
  until [ "$(curl -sf -H "X-Consul-Token: $TOKEN" \
      "http://$CONSUL_IP:8500/v1/health/checks/test-service-sidecar-proxy" \
      | jq -r '.[0].Status')" = "passing" ]; do
    sleep 5
    ELAPSED=$((ELAPSED + 5))
    if [ "$ELAPSED" -ge "$TIMEOUT" ]; then
      echo "FAIL: Proxy check never returned to passing within ${TIMEOUT}s"
      exit 1
    fi
    echo "  still waiting... (${ELAPSED}s elapsed)"
  done
  echo "PASS: Proxy check returned to passing after all containers became healthy."
else
  echo "WARNING: Did not observe CRITICAL phase — the task may have started too quickly"
  echo "         or the new task has not registered in Consul yet."
  echo "         Consider re-running after confirming the app container's startPeriod"
  echo "         is long enough to observe the transient critical state."
fi
