#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TF_DIR="$(cd "$SCRIPT_DIR/../terraform" && pwd)"

CONSUL_IP=$(terraform -chdir="$TF_DIR" output -raw consul_server_ip)
TOKEN=$(terraform -chdir="$TF_DIR" output -raw consul_token 2>/dev/null || echo "${CONSUL_TOKEN}")
CLUSTER=$(terraform -chdir="$TF_DIR" output -raw ecs_cluster_name)
SERVICE=$(terraform -chdir="$TF_DIR" output -raw ecs_service_name)

echo "=== Waiting for ECS service to stabilize ==="
aws ecs wait services-stable --cluster "$CLUSTER" --services "$SERVICE"
echo "ECS service is stable."

echo ""
echo "=== Checking Consul service registration ==="
RESULT=$(curl -sf -H "X-Consul-Token: $TOKEN" \
  "http://$CONSUL_IP:8500/v1/health/service/test-service")

PASSING=$(echo "$RESULT" | jq '[.[] | select(.Checks[].Status == "passing")] | length')

if [ "$PASSING" -gt "0" ]; then
  echo "PASS: Service registered and checks passing (passing instances: $PASSING)"
else
  echo "FAIL: No passing checks found"
  echo "Raw response:"
  echo "$RESULT" | jq .
  exit 1
fi
