#!/usr/bin/env bash
# Stop local builds: remove sci-path images/build cache, enable IMAGE_* from ECR, pull + start.
# Run on EC2 after ECR has images (GitHub Actions workflow_dispatch "all" or manual push).
#
#   bash scripts/ec2/switch-to-ecr-pull.sh
#   bash scripts/ec2/switch-to-ecr-pull.sh --dry-run

set -euo pipefail

DRY_RUN=0
if [ "${1:-}" = "--dry-run" ]; then
  DRY_RUN=1
fi

APP_DIR="/opt/sci-path/deployment-orchestration"
REG="011877215030.dkr.ecr.ap-south-1.amazonaws.com"

run() {
  if [ "$DRY_RUN" = "1" ]; then
    echo "[dry-run] $*"
  else
    "$@"
  fi
}

echo "==> Disk before cleanup"
df -h /
docker system df 2>/dev/null || true

cd "$APP_DIR"

if [ ! -f .env ]; then
  echo "Missing $APP_DIR/.env"
  exit 1
fi

echo ""
echo "==> Stopping compose stack..."
run docker compose down --remove-orphans || true

echo ""
echo "==> Removing local sci-path images and build cache..."
if [ "$DRY_RUN" = "1" ]; then
  docker images --format '{{.Repository}}:{{.Tag}}' | grep -E '^sci-path-' || true
else
  docker images --format '{{.Repository}}:{{.Tag}}' | grep -E '^sci-path-' | xargs -r docker rmi -f || true
  docker builder prune -af || true
  docker system prune -af || true
fi

echo ""
echo "==> Enabling ECR IMAGE_* in .env..."
ENV_BLOCK="
ECR_REGISTRY=${REG}
IMAGE_LPE=${REG}/sci-path/lpe:latest
IMAGE_UM=${REG}/sci-path/um:latest
IMAGE_GAMING=${REG}/sci-path/gaming:latest
IMAGE_ANALYTICS=${REG}/sci-path/analytics:latest
IMAGE_IAE=${REG}/sci-path/iae:latest
"

if [ "$DRY_RUN" = "1" ]; then
  echo "$ENV_BLOCK"
else
  # Uncomment any commented IMAGE_* / ECR_REGISTRY lines
  sed -i 's|^# ECR_REGISTRY=|ECR_REGISTRY=|' .env
  sed -i 's|^# IMAGE_LPE=|IMAGE_LPE=|' .env
  sed -i 's|^# IMAGE_UM=|IMAGE_UM=|' .env
  sed -i 's|^# IMAGE_GAMING=|IMAGE_GAMING=|' .env
  sed -i 's|^# IMAGE_ANALYTICS=|IMAGE_ANALYTICS=|' .env
  sed -i 's|^# IMAGE_IAE=|IMAGE_IAE=|' .env
  # Ensure lines exist (append if missing)
  grep -q '^ECR_REGISTRY=' .env || echo "ECR_REGISTRY=${REG}" >> .env
  grep -q '^IMAGE_LPE=' .env || echo "IMAGE_LPE=${REG}/sci-path/lpe:latest" >> .env
  grep -q '^IMAGE_UM=' .env || echo "IMAGE_UM=${REG}/sci-path/um:latest" >> .env
  grep -q '^IMAGE_GAMING=' .env || echo "IMAGE_GAMING=${REG}/sci-path/gaming:latest" >> .env
  grep -q '^IMAGE_ANALYTICS=' .env || echo "IMAGE_ANALYTICS=${REG}/sci-path/analytics:latest" >> .env
  grep -q '^IMAGE_IAE=' .env || echo "IMAGE_IAE=${REG}/sci-path/iae:latest" >> .env
fi

echo ""
echo "==> Pulling from ECR and starting (no build)..."
if [ "$DRY_RUN" = "1" ]; then
  echo "Would run: bash scripts/ec2/deploy.sh all"
else
  bash scripts/ec2/deploy.sh all
fi

echo ""
echo "==> Disk after ECR pull"
df -h /
docker system df 2>/dev/null || true
docker compose ps

echo ""
echo "Done. ECR pull mode active — future deploys: bash scripts/ec2/deploy.sh <service>"
