#!/usr/bin/env bash
# EC2 deploy helper (Phase 2 — after ECR + EC2 exist).
# Usage on instance:
#   bash scripts/ec2/deploy.sh all
#   bash scripts/ec2/deploy.sh iae

set -euo pipefail

SERVICE="${1:-all}"
APP_DIR="/opt/sci-path/deployment-orchestration"

if [ ! -f "$APP_DIR/.env" ]; then
  echo "Missing $APP_DIR/.env — copy from .env.example and fill secrets."
  exit 1
fi

if [ -z "${ECR_REGISTRY:-}" ]; then
  echo "ECR_REGISTRY is not set."
  echo "Phase 2: export ECR_REGISTRY=123456789.dkr.ecr.ap-south-1.amazonaws.com"
  echo "Then: aws ecr get-login-password | docker login ..."
  echo "Then re-run this script."
  exit 1
fi

cd "$APP_DIR"
git pull --ff-only
git submodule update --init --recursive

case "$SERVICE" in
  all)
    docker compose pull
    docker compose up -d
    ;;
  lpe|um|gaming|analytics|iae)
    docker compose pull "$SERVICE" 2>/dev/null || docker compose pull
    docker compose up -d
    ;;
  *)
    echo "Unknown service: $SERVICE (use all|lpe|um|gaming|analytics|iae)"
    exit 1
    ;;
esac

docker compose ps
