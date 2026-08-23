#!/usr/bin/env bash
# Allocate an Elastic IP and associate it with an EC2 instance (stable public address).
#
# Prerequisites:
#   - AWS CLI v2 installed and configured (aws configure / IAM role)
#   - EC2 instance already created and running
#
# Usage:
#   bash scripts/ec2/allocate-elastic-ip.sh
#   bash scripts/ec2/allocate-elastic-ip.sh i-0abc123def456
#   AWS_REGION=ap-south-1 bash scripts/ec2/allocate-elastic-ip.sh
#
# After success, put the printed IP into:
#   deployment-orchestration/.env  →  EC2_HOST=<ip>
#   frontend-app env               →  API_PROXY_TARGET=http://<ip>:8000  etc.

set -euo pipefail

REGION="${AWS_REGION:-${AWS_DEFAULT_REGION:-ap-south-1}}"
INSTANCE_ID="${1:-}"

echo "==> Region: $REGION"

if ! command -v aws >/dev/null 2>&1; then
  echo "AWS CLI not found. Install: https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html"
  exit 1
fi

aws sts get-caller-identity --region "$REGION" >/dev/null

if [ -z "$INSTANCE_ID" ]; then
  echo "==> Looking for running EC2 instances..."
  mapfile -t ROWS < <(
    aws ec2 describe-instances \
      --region "$REGION" \
      --filters "Name=instance-state-name,Values=running" \
      --query "Reservations[].Instances[].[InstanceId,Tags[?Key=='Name']|[0].Value,PublicIpAddress]" \
      --output text
  )
  if [ "${#ROWS[@]}" -eq 0 ]; then
    echo "No running instances in $REGION. Start/create an EC2 instance first, then re-run."
    exit 1
  fi
  echo "Running instances:"
  i=1
  for row in "${ROWS[@]}"; do
    echo "  [$i] $row"
    i=$((i + 1))
  done
  if [ "${#ROWS[@]}" -eq 1 ]; then
    INSTANCE_ID=$(echo "${ROWS[0]}" | awk '{print $1}')
    echo "==> Using only instance: $INSTANCE_ID"
  else
    read -r -p "Enter instance id (i-...): " INSTANCE_ID
  fi
fi

if [[ ! "$INSTANCE_ID" =~ ^i- ]]; then
  echo "Invalid instance id: $INSTANCE_ID"
  exit 1
fi

# Reuse EIP already on this instance
EXISTING=$(
  aws ec2 describe-addresses \
    --region "$REGION" \
    --filters "Name=instance-id,Values=$INSTANCE_ID" \
    --query "Addresses[0].PublicIp" \
    --output text 2>/dev/null || true
)
if [ -n "$EXISTING" ] && [ "$EXISTING" != "None" ]; then
  echo ""
  echo "Already has Elastic IP: $EXISTING"
  echo "Set EC2_HOST=$EXISTING in .env"
  echo "Frontend example:"
  echo "  API_PROXY_TARGET=http://$EXISTING:8000"
  echo "  USER_API_PROXY_TARGET=http://$EXISTING:8001"
  echo "  ASSESSMENT_API_PROXY_TARGET=http://$EXISTING:8004"
  echo "  NEXT_PUBLIC_API_URL=http://$EXISTING:8003"
  exit 0
fi

echo "==> Allocating Elastic IP..."
ALLOC_ID=$(
  aws ec2 allocate-address \
    --region "$REGION" \
    --domain vpc \
    --tag-specifications "ResourceType=elastic-ip,Tags=[{Key=Name,Value=sci-path-eip}]" \
    --query "AllocationId" \
    --output text
)
PUBLIC_IP=$(
  aws ec2 describe-addresses \
    --region "$REGION" \
    --allocation-ids "$ALLOC_ID" \
    --query "Addresses[0].PublicIp" \
    --output text
)
echo "    AllocationId=$ALLOC_ID  PublicIp=$PUBLIC_IP"

echo "==> Associating with $INSTANCE_ID..."
aws ec2 associate-address \
  --region "$REGION" \
  --instance-id "$INSTANCE_ID" \
  --allocation-id "$ALLOC_ID" \
  --allow-reassociation >/dev/null

echo ""
echo "Done. Stable public address:"
echo "  $PUBLIC_IP"
echo ""
echo "Next:"
echo "  1. Security group: allow inbound TCP 8000-8004 (and 22 for SSH) from your IPs"
echo "  2. In deployment-orchestration/.env set:"
echo "       EC2_HOST=$PUBLIC_IP"
echo "       IAE_API_BASE_URL=http://$PUBLIC_IP:8004"
echo "       CORS_ORIGINS=http://localhost:3000,https://your-frontend-domain"
echo "  3. Frontend env (Vercel / .env.local):"
echo "       API_PROXY_TARGET=http://$PUBLIC_IP:8000"
echo "       USER_API_PROXY_TARGET=http://$PUBLIC_IP:8001"
echo "       ASSESSMENT_API_PROXY_TARGET=http://$PUBLIC_IP:8004"
echo "       NEXT_PUBLIC_API_URL=http://$PUBLIC_IP:8003"
echo ""
echo "Note: EIP is free while attached to a running instance. Release it if you delete the server."
