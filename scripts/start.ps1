Write-Host "🚀 Starting Full System..." -ForegroundColor Cyan

# Step 1: Update all submodules
Write-Host "🔄 Updating services..." -ForegroundColor Yellow
powershell -ExecutionPolicy Bypass -File .\scripts\update-submodules.ps1

# Step 2: Build and start containers
Write-Host "🐳 Starting Docker containers..." -ForegroundColor Yellow
docker-compose up --build

Write-Host "✅ System is running!" -ForegroundColor Green