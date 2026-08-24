#!/usr/bin/env bash
# Install systemd unit: on EC2 start, pull :latest from ECR and start this box's profile.
# Run once per instance:
#   sudo bash scripts/ec2/install-boot-pull.sh

set -euo pipefail

APP_DIR="/opt/sci-path/deployment-orchestration"
UNIT_SRC="$APP_DIR/scripts/ec2/sci-path-boot.service"
UNIT_DST="/etc/systemd/system/sci-path-boot.service"

if [ "$(id -u)" -ne 0 ]; then
  echo "Run with sudo: sudo bash scripts/ec2/install-boot-pull.sh"
  exit 1
fi

if [ ! -f "$UNIT_SRC" ]; then
  echo "Missing $UNIT_SRC — git pull in $APP_DIR first."
  exit 1
fi

if [ ! -f "$APP_DIR/.env" ]; then
  echo "Missing $APP_DIR/.env — copy env before enabling boot pull."
  exit 1
fi

cp "$UNIT_SRC" "$UNIT_DST"
systemctl daemon-reload
systemctl enable sci-path-boot.service

echo "Enabled sci-path-boot.service"
echo "On next start (or now): sudo systemctl start sci-path-boot.service"
echo "Logs: journalctl -u sci-path-boot.service -e"
