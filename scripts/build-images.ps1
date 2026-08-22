# Build all (or one) service image(s) from git submodules into :local tags.
# Does not start containers. Run from repo root.
# First: git submodule update --init --recursive
#
#   .\scripts\build-images.ps1
#   .\scripts\build-images.ps1 -Service iae

param(
  [ValidateSet("all", "lpe", "um", "gaming", "analytics", "iae")]
  [string]$Service = "all"
)

$ErrorActionPreference = "Stop"

function Build-One([string]$Name, [string]$Context, [string]$Tag, [string]$Dockerfile = "Dockerfile") {
  Write-Host "Building $Name → $Tag" -ForegroundColor Cyan
  if (-not (Test-Path $Context)) {
    throw "Missing $Context — run: git submodule update --init --recursive"
  }
  if ($Dockerfile -eq "Dockerfile") {
    docker build -t $Tag $Context
  } else {
    docker build -f (Join-Path $Context $Dockerfile) -t $Tag $Context
  }
}

if ($Service -eq "all" -or $Service -eq "lpe") {
  Build-One "LPE" ".\services\learning-path-engine\backend" "sci-path-lpe:local"
}
if ($Service -eq "all" -or $Service -eq "um") {
  Build-One "UM" ".\services\user-management\backend" "sci-path-um:local"
}
if ($Service -eq "all" -or $Service -eq "gaming") {
  Build-One "Gaming" ".\services\gaming-service\backend" "sci-path-gaming:local"
}
if ($Service -eq "all" -or $Service -eq "analytics") {
  Build-One "Analytics" ".\services\learner-analytics-genai-support" "sci-path-analytics:local" "FastAPI-Backend\Dockerfile"
}
if ($Service -eq "all" -or $Service -eq "iae") {
  Build-One "IAE" ".\services\intelligent-assessment-engine" "sci-path-iae:local"
}

Write-Host "Done. Start with: .\scripts\start.ps1" -ForegroundColor Green
