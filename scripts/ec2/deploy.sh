#!/usr/bin/env bash
# EC2 deploy helper — pull from ECR and restart compose services.
# Usage on instance:
#   bash scripts/ec2/deploy.sh all       # all profiles (or COMPOSE_PROFILES from .env)
#   bash scripts/ec2/deploy.sh core      # LPE + UM + gaming
#   bash scripts/ec2/deploy.sh analytics
#   bash scripts/ec2/deploy.sh iae
#
# Requires in .env: ECR_REGISTRY, AWS_REGION (and AWS credentials or instance role).
# Split EC2: set COMPOSE_PROFILES=core|analytics|iae (see docs/ecr-pipeline.md).

set -euo pipefail

SERVICE="${1:-all}"
APP_DIR="/opt/sci-path/deployment-orchestration"

if [ ! -f "$APP_DIR/.env" ]; then
  echo "Missing $APP_DIR/.env — copy from .env.example and fill secrets."
  exit 1
fi

cd "$APP_DIR"

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
GIT_TERMINAL_PROMPT=0 git -c credential.helper= pull --ff-only \
  || echo "WARN: git pull failed (continuing with current tree)"

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

up_profiles() {
  local profiles="$1"
  # shellcheck disable=SC2086
  docker compose $profiles pull
  # shellcheck disable=SC2086
  docker compose $profiles up -d --no-build
}

case "$SERVICE" in
  all)
    echo "==> Pulling (COMPOSE_PROFILES=${COMPOSE_PROFILES:-core,analytics,iae})..."
    if [ -n "${COMPOSE_PROFILES:-}" ]; then
      docker compose pull
      docker compose up -d --no-build
    else
      up_profiles "--profile core --profile analytics --profile iae"
    fi
    ;;
  core)
    echo "==> Pulling core profile (LPE + UM + gaming)..."
    up_profiles "--profile core"
    ;;
  analytics)
    echo "==> Pulling analytics profile..."
    up_profiles "--profile analytics"
    ;;
  iae)
    echo "==> Pulling IAE profile..."
    up_profiles "--profile iae"
    ;;
  lpe|um|gaming)
    COMPOSE_NAME="$(compose_svc "$SERVICE")"
    echo "==> Pulling $COMPOSE_NAME..."
    docker compose --profile core pull "$COMPOSE_NAME"
    docker compose --profile core up -d --no-build "$COMPOSE_NAME"
    ;;
  *)
    echo "Unknown service: $SERVICE (use all|core|lpe|um|gaming|analytics|iae)"
    exit 1
    ;;
esac

echo ""
docker compose --profile core --profile analytics --profile iae ps
