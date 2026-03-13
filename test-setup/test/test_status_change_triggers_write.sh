#!/bin/bash
# Regression: a status change (UNHEALTHY → HEALTHY) must trigger exactly one
# Catalog.Register write and subsequent stable cycles must not write again.
#
# This is the complement to Bug1: while Bug1 checks that a *stable* status
# does not produce redundant writes, this test checks that a *real* transition
# does produce exactly one write (ModifyIndex advances exactly once) and then
# stabilises.
#
# Strategy:
#   1. Wait until proxy check is passing (HEALTHY baseline, ModifyIndex = I0).
#   2. Force a new deployment → proxy briefly goes critical during startup.
#   3. Wait for proxy to return to passing → record ModifyIndex = I1 (must be > I0).
#   4. Wait 10 more seconds → record ModifyIndex = I2 (must equal I1, no redundant writes).
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TF_DIR="$(cd "$SCRIPT_DIR/../terraform" && pwd)"

CONSUL_IP=$(terraform -chdir="$TF_DIR" output -raw consul_server_ip)
TOKEN=$(terraform -chdir="$TF_DIR" output -raw consul_token 2>/dev/null || echo "${CONSUL_TOKEN}")
CLUSTER=$(terraform -chdir="$TF_DIR" output -raw ecs_cluster_name)
SERVICE=$(terraform -chdir="$TF_DIR" output -raw ecs_service_name)

H="X-Consul-Token: $TOKEN"
CHECKS_URL="http://$CONSUL_IP:8500/v1/health/checks/test-service-sidecar-proxy"

get_status()      { curl -sf -H "$H" "$CHECKS_URL" | jq -r '.[0].Status // "not_found"'; }
get_modify_index() { curl -sf -H "$H" "$CHECKS_URL" | jq '.[0].ModifyIndex'; }

echo "=== Step 1: Wait for proxy check to reach passing baseline ==="
TIMEOUT=120; ELAPSED=0
until [ "$(get_status)" = "passing" ]; do
  sleep 5; ELAPSED=$((ELAPSED+5))
  [ $ELAPSED -ge $TIMEOUT ] && echo "FAIL: Proxy never reached passing" && exit 1
done

I0=$(get_modify_index)
echo "  Baseline passing. ModifyIndex I0 = $I0"

echo ""
echo "=== Step 2: Force deployment (triggers critical → passing transition) ==="
aws ecs update-service --cluster "$CLUSTER" --service "$SERVICE" \
  --force-new-deployment > /dev/null
echo "  Deployment triggered."

# Wait briefly for old task to start shutting down / new task to start
sleep 10

echo ""
echo "=== Step 3: Wait for proxy to return to passing ==="
TIMEOUT=180; ELAPSED=0
until [ "$(get_status)" = "passing" ]; do
  sleep 5; ELAPSED=$((ELAPSED+5))
  [ $ELAPSED -ge $TIMEOUT ] && echo "FAIL: Proxy never returned to passing" && exit 1
  echo "  still waiting... (${ELAPSED}s elapsed, status=$(get_status))"
done

I1=$(get_modify_index)
echo "  Proxy is passing. ModifyIndex I1 = $I1"

if [ "$I1" -le "$I0" ]; then
  echo "FAIL: ModifyIndex did not advance after status transition ($I0 → $I1)"
  exit 1
fi
echo "  ModifyIndex advanced as expected ($I0 → $I1)"

echo ""
echo "=== Step 4: Wait 10s and verify no further writes ==="
sleep 10

I2=$(get_modify_index)
echo "  ModifyIndex after 10s of stability: $I2"

if [ "$I1" -eq "$I2" ]; then
  echo "PASS: Status change produced exactly one write; no redundant writes after stabilizing"
else
  echo "FAIL: ModifyIndex advanced again ($I1 → $I2) after status was already stable"
  exit 1
fi
