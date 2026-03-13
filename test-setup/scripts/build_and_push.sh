#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

REGION=$(terraform -chdir="$REPO_ROOT/terraform" output -raw region 2>/dev/null || echo "ap-south-1")
ECR_URL=$(terraform -chdir="$REPO_ROOT/terraform" output -raw ecr_repository_url)
ACCOUNT=$(aws sts get-caller-identity --query Account --output text)

echo "=== Logging in to ECR ==="
aws ecr get-login-password --region "$REGION" | \
  docker login --username AWS --password-stdin "$ECR_URL"

echo "=== Building consul-ecs image ==="
docker build -t consul-ecs:latest "$REPO_ROOT"

echo "=== Tagging and pushing ==="
docker tag consul-ecs:latest "$ECR_URL:latest"
docker push "$ECR_URL:latest"

echo ""
echo "Pushed to $ECR_URL:latest"
