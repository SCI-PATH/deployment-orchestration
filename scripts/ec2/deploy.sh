#!/usr/bin/env bash
# EC2 deploy helper — pull from ECR and restart compose services.
# Usage on instance:
#   bash scripts/ec2/deploy.sh all
#   bash scripts/ec2/deploy.sh iae
#
# Requires in .env: ECR_REGISTRY, AWS_REGION (and AWS credentials or instance role).
# For ECR pulls, set IMAGE_* URIs in .env (see docs/ecr-pipeline.md).

set -euo pipefail

SERVICE="${1:-all}"
APP_DIR="/opt/sci-path/deployment-orchestration"

if [ ! -f "$APP_DIR/.env" ]; then
  echo "Missing $APP_DIR/.env — copy from .env.example and fill secrets."
  exit 1
fi

cd "$APP_DIR"

# Load ECR_REGISTRY / AWS_REGION / IMAGE_* without exporting unrelated secrets into the shell log
set -a
# shellcheck disable=SC1091
source .env
set +a

if [ -z "${ECR_REGISTRY:-}" ]; then
  echo "ECR_REGISTRY is not set in $APP_DIR/.env"
  echo "Example: ECR_REGISTRY=011877215030.dkr.ecr.ap-south-1.amazonaws.com"
  exit 1
fi

REGION="${AWS_REGION:-${AWS_DEFAULT_REGION:-ap-south-1}}"

echo "==> Logging in to ECR ($ECR_REGISTRY)..."
if ! command -v aws >/dev/null 2>&1; then
  echo "AWS CLI not found. Install it, or attach an IAM instance role and install awscli."
  echo "  sudo apt-get update && sudo apt-get install -y awscli"
  exit 1
fi

aws ecr get-login-password --region "$REGION" \
  | docker login --username AWS --password-stdin "$ECR_REGISTRY"

echo "==> Refreshing orchestration repo (compose + scripts only)..."
git pull --ff-only || echo "WARN: git pull failed (continuing with current tree)"

# Short name → docker compose service name
compose_svc() {
  case "$1" in
    lpe) echo "learning-path-engine" ;;
    um) echo "user-management" ;;
    gaming) echo "gaming-backend" ;;
    analytics) echo "learner-analytics" ;;
    iae) echo "intelligent-assessment-engine" ;;
    *) return 1 ;;
  esac
}

case "$SERVICE" in
  all)
    echo "==> Pulling all images..."
    docker compose pull
    docker compose up -d --no-build
    ;;
  lpe|um|gaming|analytics|iae)
    COMPOSE_NAME="$(compose_svc "$SERVICE")"
    echo "==> Pulling $COMPOSE_NAME..."
    docker compose pull "$COMPOSE_NAME"
    docker compose up -d --no-build "$COMPOSE_NAME"
    ;;
  *)
    echo "Unknown service: $SERVICE (use all|lpe|um|gaming|analytics|iae)"
    exit 1
    ;;
esac

echo ""
docker compose ps
