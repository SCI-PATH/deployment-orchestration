# Allocate an Elastic IP and associate it with an EC2 instance (stable public address).
#
# Prerequisites:
#   - AWS CLI v2 installed and configured (aws configure)
#   - EC2 instance already created and running
#
# Usage:
#   .\scripts\ec2\allocate-elastic-ip.ps1
#   .\scripts\ec2\allocate-elastic-ip.ps1 -InstanceId i-0abc123def456
#   $env:AWS_REGION = "ap-south-1"; .\scripts\ec2\allocate-elastic-ip.ps1
#
# After success, put the printed IP into:
#   deployment-orchestration/.env  →  EC2_HOST=<ip>
#   frontend-app env               →  API_PROXY_TARGET=http://<ip>:8000  etc.

param(
  [string]$InstanceId = "",
  [string]$Region = $(if ($env:AWS_REGION) { $env:AWS_REGION } elseif ($env:AWS_DEFAULT_REGION) { $env:AWS_DEFAULT_REGION } else { "ap-south-1" })
)

$ErrorActionPreference = "Stop"

if (-not (Get-Command aws -ErrorAction SilentlyContinue)) {
  Write-Host "AWS CLI not found. Install: https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html"
  Write-Host "Or use the Console steps in docs/elastic-ip.md"
  exit 1
}

Write-Host "==> Region: $Region"
aws sts get-caller-identity --region $Region | Out-Null

if (-not $InstanceId) {
  Write-Host "==> Looking for running EC2 instances..."
  $raw = aws ec2 describe-instances `
    --region $Region `
    --filters "Name=instance-state-name,Values=running" `
    --query "Reservations[].Instances[].[InstanceId,Tags[?Key=='Name']|[0].Value,PublicIpAddress]" `
    --output text
  $rows = @($raw -split "`n" | Where-Object { $_.Trim() })
  if ($rows.Count -eq 0) {
    Write-Host "No running instances in $Region. Start your EC2 first, then re-run."
    exit 1
  }
  Write-Host "Running instances:"
  for ($i = 0; $i -lt $rows.Count; $i++) {
    Write-Host ("  [{0}] {1}" -f ($i + 1), $rows[$i])
  }
  if ($rows.Count -eq 1) {
    $InstanceId = ($rows[0] -split "\s+")[0]
    Write-Host "==> Using only instance: $InstanceId"
  } else {
    $InstanceId = Read-Host "Enter instance id (i-...)"
  }
}

if ($InstanceId -notmatch '^i-') {
  Write-Host "Invalid instance id: $InstanceId"
  exit 1
}

$existing = aws ec2 describe-addresses `
  --region $Region `
  --filters "Name=instance-id,Values=$InstanceId" `
  --query "Addresses[0].PublicIp" `
  --output text 2>$null

if ($existing -and $existing -ne "None" -and $existing.Trim()) {
  Write-Host ""
  Write-Host "Already has Elastic IP: $existing"
  Write-Host "Set EC2_HOST=$existing in .env"
  Write-Host "Frontend example:"
  Write-Host "  API_PROXY_TARGET=http://$existing`:8000"
  Write-Host "  USER_API_PROXY_TARGET=http://$existing`:8001"
  Write-Host "  ASSESSMENT_API_PROXY_TARGET=http://$existing`:8004"
  Write-Host "  NEXT_PUBLIC_API_URL=http://$existing`:8003"
  exit 0
}

Write-Host "==> Allocating Elastic IP..."
$allocId = aws ec2 allocate-address `
  --region $Region `
  --domain vpc `
  --tag-specifications "ResourceType=elastic-ip,Tags=[{Key=Name,Value=sci-path-eip}]" `
  --query "AllocationId" `
  --output text

$publicIp = aws ec2 describe-addresses `
  --region $Region `
  --allocation-ids $allocId `
  --query "Addresses[0].PublicIp" `
  --output text

Write-Host "    AllocationId=$allocId  PublicIp=$publicIp"

Write-Host "==> Associating with $InstanceId..."
aws ec2 associate-address `
  --region $Region `
  --instance-id $InstanceId `
  --allocation-id $allocId `
  --allow-reassociation | Out-Null

Write-Host ""
Write-Host "Done. Stable public address:"
Write-Host "  $publicIp"
Write-Host ""
Write-Host "Next:"
Write-Host "  1. Security group: allow inbound TCP 8000-8004 (and 22 for SSH)"
Write-Host "  2. In deployment-orchestration/.env set:"
Write-Host "       EC2_HOST=$publicIp"
Write-Host "       IAE_API_BASE_URL=http://$publicIp`:8004"
Write-Host "  3. Frontend env:"
Write-Host "       API_PROXY_TARGET=http://$publicIp`:8000"
Write-Host "       USER_API_PROXY_TARGET=http://$publicIp`:8001"
Write-Host "       ASSESSMENT_API_PROXY_TARGET=http://$publicIp`:8004"
Write-Host "       NEXT_PUBLIC_API_URL=http://$publicIp`:8003"
Write-Host ""
Write-Host "Note: EIP is free while attached to a running instance."
Write-Host "Full guide: docs/elastic-ip.md"
