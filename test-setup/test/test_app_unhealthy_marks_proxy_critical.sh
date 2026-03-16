#!/bin/bash
# Regression: when the app container ECS health check transitions to UNHEALTHY,
# health-sync must mark the proxy check critical. This exercises the
# ecsHealthToConsulHealth mapping and computeOverallDataplaneHealth path.
#
# Strategy: use ECS Exec to SIGSTOP nginx (pauses the process without killing
# the container), causing the ECS health check to time out → UNHEALTHY.
# Then SIGCONT resumes nginx to restore the healthy state.
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TF_DIR="$(cd "$SCRIPT_DIR/../terraform" && pwd)"

REGION=$(terraform -chdir="$TF_DIR" output -raw region)
CONSUL_IP=$(terraform -chdir="$TF_DIR" output -raw consul_server_ip)
TOKEN=$(terraform -chdir="$TF_DIR" output -raw consul_token 2>/dev/null || echo "${CONSUL_TOKEN}")
CLUSTER=$(terraform -chdir="$TF_DIR" output -raw ecs_cluster_name)
SERVICE=$(terraform -chdir="$TF_DIR" output -raw ecs_service_name)

H="X-Consul-Token: $TOKEN"
CHECKS_URL="http://$CONSUL_IP:8500/v1/health/checks/test-service-sidecar-proxy"

get_proxy_status() { curl -sf -H "$H" "$CHECKS_URL" | jq -r '.[0].Status // "not_found"'; }

echo "=== Waiting for proxy check to be passing before the test ==="
TIMEOUT=120; ELAPSED=0
until [ "$(get_proxy_status)" = "passing" ]; do
  sleep 5; ELAPSED=$((ELAPSED+5))
  [ $ELAPSED -ge $TIMEOUT ] && echo "FAIL: Proxy never reached passing before test" && exit 1
done
echo "  Proxy check is passing. Proceeding."

echo ""
echo "=== Finding running task ARN ==="
TASK_ARN=$(aws ecs list-tasks --region "$REGION" --cluster "$CLUSTER" \
  --service-name "$SERVICE" --query 'taskArns[0]' --output text)
if [ -z "$TASK_ARN" ] || [ "$TASK_ARN" = "None" ]; then
  echo "FAIL: No running task found"
  exit 1
fi
echo "  Task ARN: $TASK_ARN"

echo ""
echo "=== Creating /tmp/sick flag to trigger UNHEALTHY ==="
# The app health check is: [ ! -f /tmp/sick ] && wget ... || exit 1
# Creating /tmp/sick causes the health check to exit 1 → ECS marks UNHEALTHY.
aws ecs execute-command \
  --region "$REGION" \
  --cluster "$CLUSTER" \
  --task "$TASK_ARN" \
  --container app \
  --interactive \
  --command "touch /tmp/sick" 2>/dev/null || true
echo "  Flag file created. Waiting up to 60s for proxy check to go critical..."

CAUGHT_CRITICAL=false
for i in $(seq 1 20); do
  STATUS=$(get_proxy_status)
  echo "  [$i] proxy check status: $STATUS"
  if [ "$STATUS" = "critical" ]; then
    CAUGHT_CRITICAL=true
    break
  fi
  sleep 3
done

echo ""
echo "=== Removing /tmp/sick flag to restore HEALTHY ==="
aws ecs execute-command \
  --region "$REGION" \
  --cluster "$CLUSTER" \
  --task "$TASK_ARN" \
  --container app \
  --interactive \
  --command "rm -f /tmp/sick" 2>/dev/null || true
echo "  Flag file removed."

if $CAUGHT_CRITICAL; then
  echo "PASS: Proxy check went critical when app container became unhealthy"
else
  echo "FAIL: Proxy check never went critical after app became unhealthy"
  exit 1
fi

echo ""
echo "=== Waiting for proxy check to return to passing ==="
TIMEOUT=120; ELAPSED=0
until [ "$(get_proxy_status)" = "passing" ]; do
  sleep 5; ELAPSED=$((ELAPSED+5))
  [ $ELAPSED -ge $TIMEOUT ] && echo "FAIL: Proxy never recovered to passing" && exit 1
done
echo "  Proxy check returned to passing."
