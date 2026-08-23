# One-time (or after PDF update) Chroma ingest for LPE, IAE, and Analytics.
# Requires stack running: docker compose up -d
# Usage: .\scripts\ingest-chromas.ps1
#        .\scripts\ingest-chromas.ps1 -SkipLpe   # IAE + Analytics only

param(
  [switch]$SkipLpe,
  [switch]$SkipIae,
  [switch]$SkipAnalytics
)

$ErrorActionPreference = "Stop"
Set-Location (Split-Path $PSScriptRoot -Parent)

if (-not (Test-Path ".env")) {
  Write-Host "Missing .env — copy .env.example and fill secrets first." -ForegroundColor Red
  exit 1
}

$textbooksPath = $env:TEXTBOOKS_HOST_PATH
if (-not $textbooksPath) {
  $textbooksPath = "../learning-path-engine/backend/data/textbooks"
}
$textbooksPath = (Resolve-Path $textbooksPath -ErrorAction SilentlyContinue)
if (-not $textbooksPath) {
  Write-Host "Textbooks not found. Set TEXTBOOKS_HOST_PATH in .env to the folder with Grade 6–9 PDFs." -ForegroundColor Red
  exit 1
}

Write-Host "Using textbooks: $textbooksPath" -ForegroundColor Cyan

function Invoke-ComposeExec {
  param([string]$Service, [string[]]$Command)
  & docker compose exec -T $Service @Command
  if ($LASTEXITCODE -ne 0) { throw "Command failed on $Service" }
}

if (-not $SkipLpe) {
  Write-Host "`n==> LPE textbook ingest..." -ForegroundColor Yellow
  Invoke-ComposeExec "learning-path-engine" @("python", "scripts/ingest.py")
  Invoke-ComposeExec "learning-path-engine" @(
    "python", "-c",
    "import urllib.request, json; r=urllib.request.urlopen('http://127.0.0.1:8000/debug/chroma-stats'); print(json.loads(r.read()))"
  )
}

if (-not $SkipIae) {
  Write-Host "`n==> IAE curriculum_chunks ingest (grades 6–9)..." -ForegroundColor Yellow
  foreach ($grade in 6..9) {
    Write-Host "  Grade $grade..." -ForegroundColor DarkGray
    Invoke-ComposeExec "intelligent-assessment-engine" @(
      "python", "scripts/ingest_and_tag_chunks.py", "--grade", "$grade"
    )
  }
  Invoke-ComposeExec "intelligent-assessment-engine" @(
    "python", "-c",
    "from iae.infrastructure.rag.chroma_store import ChromaChunkStore; s=ChromaChunkStore(); print('curriculum_chunks total:', s.count())"
  )
}

if (-not $SkipAnalytics) {
  Write-Host "`n==> Analytics Socrates RAG rebuild..." -ForegroundColor Yellow
  Invoke-ComposeExec "learner-analytics" @(
    "python", "-m", "FastAPI-Backend.knowledge_base", "--rebuild"
  )
}

Write-Host "`nChroma ingest complete." -ForegroundColor Green
