param(
  [switch]$Build
)

Write-Host "Starting SCI-PATH stack (local compose)..." -ForegroundColor Cyan

if (-not (Test-Path ".env")) {
  Write-Host "Missing .env - copy .env.example to .env and fill secrets first." -ForegroundColor Red
  exit 1
}

Write-Host "Updating submodules..." -ForegroundColor Yellow
powershell -ExecutionPolicy Bypass -File .\scripts\update-submodules.ps1

if ($Build) {
  Write-Host "Building images from ./services submodules, then starting..." -ForegroundColor Yellow
  docker compose up -d --build
} else {
  Write-Host "Starting containers (uses existing :local images)..." -ForegroundColor Yellow
  Write-Host "Tip: pass -Build to rebuild from ./services submodules." -ForegroundColor DarkGray
  docker compose up -d
}

Write-Host ""
Write-Host "Stack requested. Check status with: docker compose ps" -ForegroundColor Green
Write-Host "  LPE        http://127.0.0.1:8000/health"
Write-Host "  UM         http://127.0.0.1:8001/health"
Write-Host "  Gaming     http://127.0.0.1:8002/api/health"
Write-Host "  Analytics  http://127.0.0.1:8003/docs"
Write-Host "  IAE        http://127.0.0.1:8004/"
