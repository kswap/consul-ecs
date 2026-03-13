#!/bin/bash
# Run ONCE after `terraform apply`.
# SSHs into the Consul EC2 instance, bootstraps ACLs, and prints the
# management token to add to terraform.tfvars.
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

CONSUL_IP=$(terraform -chdir="$REPO_ROOT/terraform" output -raw consul_server_ip)

echo "=== Waiting for Consul to start on $CONSUL_IP ==="
until ssh -o StrictHostKeyChecking=no -o ConnectTimeout=5 \
    ec2-user@"$CONSUL_IP" "consul members" 2>/dev/null; do
  echo "  not ready yet, retrying in 3s..."
  sleep 3
done

echo ""
echo "=== Bootstrapping Consul ACLs ==="
TOKEN=$(ssh -o StrictHostKeyChecking=no ec2-user@"$CONSUL_IP" \
  "consul acl bootstrap -format=json" | jq -r '.SecretID')

echo ""
echo "Bootstrap management token:"
echo "  $TOKEN"
echo ""
echo "Add the following line to terraform/terraform.tfvars:"
echo "  consul_token = \"$TOKEN\""
echo ""
echo "Then run: terraform -chdir=terraform apply"
