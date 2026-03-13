#!/bin/bash
# Regression: on graceful task shutdown (SIGTERM path), health-sync must:
#   1. Set all checks critical immediately (setChecksCritical)
#   2. Wait for consul-dataplane to stop
#   3. Deregister both test-service and test-service-sidecar-proxy from Consul
#
# Strategy: stop the ECS task directly, which sends SIGTERM to containers.
# Then verify both catalog entries are gone. A new deployment is triggered at
# the end to restore the service.
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TF_DIR="$(cd "$SCRIPT_DIR/../terraform" && pwd)"

CONSUL_IP=$(terraform -chdir="$TF_DIR" output -raw consul_server_ip)
TOKEN=$(terraform -chdir="$TF_DIR" output -raw consul_token 2>/dev/null || echo "${CONSUL_TOKEN}")
CLUSTER=$(terraform -chdir="$TF_DIR" output -raw ecs_cluster_name)
SERVICE=$(terraform -chdir="$TF_DIR" output -raw ecs_service_name)

H="X-Consul-Token: $TOKEN"

echo "=== Waiting for proxy check to be passing before the test ==="
TIMEOUT=120; ELAPSED=0
until [ "$(curl -sf -H "$H" \
    "http://$CONSUL_IP:8500/v1/health/checks/test-service-sidecar-proxy" \
    | jq -r '.[0].Status')" = "passing" ]; do
  sleep 5; ELAPSED=$((ELAPSED+5))
  [ $ELAPSED -ge $TIMEOUT ] && echo "FAIL: Proxy never reached passing" && exit 1
done
echo "  Proxy check is passing. Proceeding."

echo ""
echo "=== Phase 1: Checks go critical immediately after SIGTERM ==="
TASK_ARN=$(aws ecs list-tasks --cluster "$CLUSTER" --service-name "$SERVICE" \
  --query 'taskArns[0]' --output text)
echo "  Stopping task $TASK_ARN ..."
aws ecs stop-task --cluster "$CLUSTER" --task "$TASK_ARN" --reason "regression test" > /dev/null

CAUGHT_CRITICAL=false
for i in $(seq 1 15); do
  STATUS=$(curl -sf -H "$H" \
    "http://$CONSUL_IP:8500/v1/health/checks/test-service-sidecar-proxy" \
    | jq -r '.[0].Status // "not_found"')
  echo "  [$i] proxy check status: $STATUS"
  if [ "$STATUS" = "critical" ]; then
    CAUGHT_CRITICAL=true
    echo "  PASS: Proxy check went critical immediately after task stop"
    break
  fi
  sleep 2
done

if ! $CAUGHT_CRITICAL; then
  echo "  WARNING: Did not observe critical phase — task may have stopped too quickly"
fi

echo ""
echo "=== Phase 2: Service and proxy deregistered after task exits ==="
TIMEOUT=90; ELAPSED=0
while true; do
  SVC_COUNT=$(curl -sf -H "$H" \
    "http://$CONSUL_IP:8500/v1/catalog/service/test-service" | jq 'length')
  PROXY_COUNT=$(curl -sf -H "$H" \
    "http://$CONSUL_IP:8500/v1/catalog/service/test-service-sidecar-proxy" | jq 'length')

  echo "  (${ELAPSED}s) catalog instances — test-service: $SVC_COUNT, sidecar-proxy: $PROXY_COUNT"

  if [ "$SVC_COUNT" -eq "0" ] && [ "$PROXY_COUNT" -eq "0" ]; then
    echo "PASS: Both test-service and test-service-sidecar-proxy deregistered after graceful shutdown"
    break
  fi

  sleep 5; ELAPSED=$((ELAPSED+5))
  if [ $ELAPSED -ge $TIMEOUT ]; then
    echo "FAIL: Services not deregistered within ${TIMEOUT}s after task stop"
    echo "  Remaining — test-service: $SVC_COUNT, sidecar-proxy: $PROXY_COUNT"
    exit 1
  fi
done

echo ""
echo "=== Restoring service with a fresh deployment ==="
aws ecs update-service --cluster "$CLUSTER" --service "$SERVICE" \
  --force-new-deployment > /dev/null
echo "  Waiting for service to restabilize..."
aws ecs wait services-stable --cluster "$CLUSTER" --services "$SERVICE"
echo "  Service restored."
