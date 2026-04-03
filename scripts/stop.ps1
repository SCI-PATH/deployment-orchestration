Write-Host "🛑 Stopping all services..." -ForegroundColor Red

docker-compose down

Write-Host "✅ All services stopped." -ForegroundColor Green