#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEST_SETUP_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
REPO_ROOT="$(cd "$TEST_SETUP_DIR/.." && pwd)"

REGION=$(terraform -chdir="$TEST_SETUP_DIR/terraform" output -raw region 2>/dev/null || echo "ap-south-1")
ECR_URL=$(terraform -chdir="$TEST_SETUP_DIR/terraform" output -raw ecr_repository_url)
ACCOUNT=$(aws sts get-caller-identity --query Account --output text)
echo "Building from repo root: $REPO_ROOT"

echo "=== Building consul-ecs binary (linux/amd64) ==="
mkdir -p "$REPO_ROOT/dist/linux/amd64"
# The Dockerfile expects a pre-built binary at dist/<os>/<arch>/consul-ecs
GOOS=linux GOARCH=amd64 go build \
  -o "$REPO_ROOT/dist/linux/amd64/consul-ecs" \
  "$REPO_ROOT"

echo "=== Logging in to ECR ==="
aws ecr get-login-password --region "$REGION" | \
  docker login --username AWS --password-stdin "$ECR_URL"

echo "=== Building consul-ecs Docker image ==="
docker build \
  --platform linux/amd64 \
  --build-arg BIN_NAME=consul-ecs \
  -t consul-ecs:latest \
  "$REPO_ROOT"

echo "=== Tagging and pushing ==="
docker tag consul-ecs:latest "$ECR_URL:latest"
docker push "$ECR_URL:latest"

echo ""
echo "Pushed to $ECR_URL:latest"
