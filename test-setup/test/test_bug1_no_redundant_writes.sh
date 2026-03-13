#!/bin/bash
# Validates Bug1 fix: proxy check ModifyIndex must not advance when health status is stable.
# Without the fix, health-sync calls Catalog().Register() on every poll cycle even when
# the status hasn't changed, causing ModifyIndex to increment continuously.
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TF_DIR="$(cd "$SCRIPT_DIR/../terraform" && pwd)"

CONSUL_IP=$(terraform -chdir="$TF_DIR" output -raw consul_server_ip)
TOKEN=$(terraform -chdir="$TF_DIR" output -raw consul_token 2>/dev/null || echo "${CONSUL_TOKEN}")

echo "=== Bug1: Checking for redundant Catalog.Register writes ==="
echo ""

# Wait for proxy check to be passing before sampling
echo "Waiting for proxy check to reach 'passing' state..."
until curl -sf -H "X-Consul-Token: $TOKEN" \
    "http://$CONSUL_IP:8500/v1/health/checks/test-service-sidecar-proxy" \
    | jq -e '.[] | select(.Status == "passing")' > /dev/null 2>&1; do
  echo "  waiting for proxy check to be passing..."
  sleep 3
done

IDX1=$(curl -sf -H "X-Consul-Token: $TOKEN" \
  "http://$CONSUL_IP:8500/v1/health/checks/test-service-sidecar-proxy" \
  | jq '.[0].ModifyIndex')
echo "  ModifyIndex before wait: $IDX1"

echo "  Waiting 10 seconds (covers ~2 health-sync poll cycles)..."
sleep 10

IDX2=$(curl -sf -H "X-Consul-Token: $TOKEN" \
  "http://$CONSUL_IP:8500/v1/health/checks/test-service-sidecar-proxy" \
  | jq '.[0].ModifyIndex')
echo "  ModifyIndex after 10s:   $IDX2"

echo ""
if [ "$IDX1" -eq "$IDX2" ]; then
  echo "PASS: No redundant writes detected (ModifyIndex stable at $IDX1)"
else
  echo "FAIL: ModifyIndex changed from $IDX1 to $IDX2 — redundant Catalog.Register writes are occurring"
  exit 1
fi
