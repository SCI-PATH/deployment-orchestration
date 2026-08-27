#!/usr/bin/env bash
# EC2 deploy helper — drop old images, pull :latest from ECR, restart compose.
# Usage on instance:
#   bash scripts/ec2/deploy.sh all       # all profiles (or COMPOSE_PROFILES from .env)
#   bash scripts/ec2/deploy.sh core      # LPE + UM + gaming
#   bash scripts/ec2/deploy.sh analytics
#   bash scripts/ec2/deploy.sh iae
#
# Flow (low disk): stop → delete old image(s) → pull only :latest → up.
# Also used by sci-path-boot.service on instance start.
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
# Analytics image historically balloons with CUDA/torch; keep headroom for pull+extract.
MIN_FREE_GB="${DEPLOY_MIN_FREE_GB:-8}"

free_gb() {
  df -BG --output=avail / | awk 'NR==2 { gsub(/G/,""); print $1 }'
}

ensure_disk_space() {
  local avail
  avail="$(free_gb)"
  echo "==> Disk free: ${avail}G (need >= ${MIN_FREE_GB}G)"
  if [ "${avail:-0}" -lt "$MIN_FREE_GB" ]; then
    echo "ERROR: not enough free disk on / (${avail}G < ${MIN_FREE_GB}G)."
    echo "Run: docker image prune -af && docker builder prune -af"
    exit 1
  fi
}

prune_unused_images() {
  echo "==> Pruning unused Docker images / build cache..."
  docker image prune -af >/dev/null || true
  docker builder prune -af >/dev/null 2>&1 || true
}

# Stop containers, delete their local images, then pull only :latest and start.
# Avoids keeping old+new side-by-side (that is what filled the analytics disk).
refresh_services() {
  local profiles="$1"
  shift
  local services=("$@")

  if [ "${#services[@]}" -eq 0 ]; then
    echo "==> Stopping profile and removing old images..."
    # shellcheck disable=SC2086
    docker compose $profiles down --rmi all --remove-orphans || \
      docker compose $profiles down --remove-orphans || true
  else
    echo "==> Stopping ${services[*]} and removing their old images..."
    # Capture image IDs while containers still exist
    local imgs=()
    # shellcheck disable=SC2086
    mapfile -t imgs < <(docker compose $profiles images -q "${services[@]}" 2>/dev/null | sort -u || true)
    # shellcheck disable=SC2086
    docker compose $profiles stop "${services[@]}" || true
    # shellcheck disable=SC2086
    docker compose $profiles rm -f "${services[@]}" || true
    local img
    for img in "${imgs[@]}"; do
      [ -n "$img" ] || continue
      echo "    removing image $img"
      docker image rm -f "$img" 2>/dev/null || true
    done
  fi

  prune_unused_images
  ensure_disk_space

  if [ "${#services[@]}" -eq 0 ]; then
    echo "==> Pulling :latest only..."
    # shellcheck disable=SC2086
    docker compose $profiles pull
    # shellcheck disable=SC2086
    docker compose $profiles up -d --no-build --remove-orphans
  else
    echo "==> Pulling :latest for ${services[*]}..."
    # shellcheck disable=SC2086
    docker compose $profiles pull "${services[@]}"
    # shellcheck disable=SC2086
    docker compose $profiles up -d --no-build --remove-orphans "${services[@]}"
  fi

  prune_unused_images
}

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

case "$SERVICE" in
  all)
    echo "==> Refresh all (COMPOSE_PROFILES=${COMPOSE_PROFILES:-core,analytics,iae})..."
    if [ -n "${COMPOSE_PROFILES:-}" ]; then
      # Box runs only its profile(s) from .env — tear down + re-pull those.
      refresh_services ""
    else
      refresh_services "--profile core --profile analytics --profile iae"
    fi
    ;;
  core)
    echo "==> Refresh core profile (LPE + UM + gaming)..."
    refresh_services "--profile core"
    ;;
  analytics)
    echo "==> Refresh analytics profile..."
    refresh_services "--profile analytics"
    ;;
  iae)
    echo "==> Refresh IAE profile..."
    refresh_services "--profile iae"
    ;;
  lpe|um|gaming)
    COMPOSE_NAME="$(compose_svc "$SERVICE")"
    echo "==> Refresh $COMPOSE_NAME..."
    refresh_services "--profile core" "$COMPOSE_NAME"
    ;;
  *)
    echo "Unknown service: $SERVICE (use all|core|lpe|um|gaming|analytics|iae)"
    exit 1
    ;;
esac

echo ""
docker compose --profile core --profile analytics --profile iae ps
echo "==> Disk free after deploy: $(free_gb)G"
