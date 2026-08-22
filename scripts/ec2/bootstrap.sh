#!/usr/bin/env bash
# First-time EC2 setup for SCI-PATH (Ubuntu 22.04+).
# Run as root or with sudo on a fresh instance:
#   sudo bash scripts/ec2/bootstrap.sh

set -euo pipefail

echo "==> Installing Docker..."
apt-get update -qq
apt-get install -y ca-certificates curl git
install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
chmod a+r /etc/apt/keyrings/docker.asc
echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu \
  $(. /etc/os-release && echo "${VERSION_CODENAME}") stable" \
  > /etc/apt/sources.list.d/docker.list
apt-get update -qq
apt-get install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin
usermod -aG docker ubuntu || true

echo "==> Creating app directory..."
APP_DIR="/opt/sci-path/deployment-orchestration"
mkdir -p /opt/sci-path
if [ ! -d "$APP_DIR/.git" ]; then
  git clone https://github.com/SCI-PATH/deployment-orchestration.git "$APP_DIR"
fi

echo "==> Next steps (manual):"
echo "  1. Copy .env to $APP_DIR/.env (Neon URLs, GROQ_API_KEY, JWT_SECRET, CORS with EC2 IP)"
echo "  2. Set IAE_API_BASE_URL=http://<EC2_PUBLIC_IP>:8004"
echo "  3. Configure AWS CLI on instance OR attach IAM role with ECR read"
echo "  4. Run: cd $APP_DIR && bash scripts/ec2/deploy.sh all"
echo ""
echo "Bootstrap complete."
