#!/bin/bash
# Regression: both test-service and test-service-sidecar-proxy must be
# registered in Consul after a task starts. A regression here means mesh-init
# failed to register one of the two catalog entries, or health-sync lost the
# proxy check mapping.
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TF_DIR="$(cd "$SCRIPT_DIR/../terraform" && pwd)"

CONSUL_IP=$(terraform -chdir="$TF_DIR" output -raw consul_server_ip)
TOKEN=$(terraform -chdir="$TF_DIR" output -raw consul_token 2>/dev/null || echo "${CONSUL_TOKEN}")
CLUSTER=$(terraform -chdir="$TF_DIR" output -raw ecs_cluster_name)
SERVICE=$(terraform -chdir="$TF_DIR" output -raw ecs_service_name)

H="X-Consul-Token: $TOKEN"

echo "=== Waiting for ECS service to stabilize ==="
aws ecs wait services-stable --cluster "$CLUSTER" --services "$SERVICE"

echo ""
echo "=== Checking test-service registration ==="
SVC=$(curl -sf -H "$H" "http://$CONSUL_IP:8500/v1/catalog/service/test-service")
COUNT=$(echo "$SVC" | jq 'length')
if [ "$COUNT" -gt "0" ]; then
  echo "PASS: test-service is registered ($COUNT instance(s))"
else
  echo "FAIL: test-service not found in Consul catalog"
  exit 1
fi

echo ""
echo "=== Checking test-service-sidecar-proxy registration ==="
PROXY=$(curl -sf -H "$H" "http://$CONSUL_IP:8500/v1/catalog/service/test-service-sidecar-proxy")
PCOUNT=$(echo "$PROXY" | jq 'length')
if [ "$PCOUNT" -gt "0" ]; then
  echo "PASS: test-service-sidecar-proxy is registered ($PCOUNT instance(s))"
else
  echo "FAIL: test-service-sidecar-proxy not found in Consul catalog"
  exit 1
fi

echo ""
echo "=== Checking health checks exist for both ==="
SVC_CHECKS=$(curl -sf -H "$H" \
  "http://$CONSUL_IP:8500/v1/health/checks/test-service" | jq 'length')
PROXY_CHECKS=$(curl -sf -H "$H" \
  "http://$CONSUL_IP:8500/v1/health/checks/test-service-sidecar-proxy" | jq 'length')

if [ "$SVC_CHECKS" -gt "0" ] && [ "$PROXY_CHECKS" -gt "0" ]; then
  echo "PASS: Health checks present for both service ($SVC_CHECKS) and proxy ($PROXY_CHECKS)"
else
  echo "FAIL: Missing health checks — service checks: $SVC_CHECKS, proxy checks: $PROXY_CHECKS"
  exit 1
fi
