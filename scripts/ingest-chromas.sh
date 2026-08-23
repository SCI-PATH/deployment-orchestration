#!/usr/bin/env bash
# One-time (or after PDF update) Chroma ingest for LPE, IAE, and Analytics.
# Requires stack running: docker compose up -d
# Usage: bash scripts/ingest-chromas.sh
#        SKIP_LPE=1 bash scripts/ingest-chromas.sh

set -euo pipefail

cd "$(dirname "$0")/.."

if [ ! -f .env ]; then
  echo "Missing .env — copy .env.example and fill secrets first."
  exit 1
fi

# shellcheck disable=SC1091
source .env 2>/dev/null || true

TEXTBOOKS="${TEXTBOOKS_HOST_PATH:-./services/learning-path-engine/backend/data/textbooks}"
if [ ! -d "$TEXTBOOKS" ]; then
  echo "Textbooks not found at $TEXTBOOKS"
  echo "Set TEXTBOOKS_HOST_PATH in .env (EC2: ./services/learning-path-engine/backend/data/textbooks)"
  exit 1
fi

echo "Using textbooks: $TEXTBOOKS"

if [ "${SKIP_LPE:-0}" != "1" ]; then
  echo ""
  echo "==> LPE textbook ingest..."
  docker compose exec -T learning-path-engine python scripts/ingest.py
  docker compose exec -T learning-path-engine python -c \
    "import urllib.request, json; r=urllib.request.urlopen('http://127.0.0.1:8000/debug/chroma-stats'); print(json.loads(r.read()))"
fi

if [ "${SKIP_IAE:-0}" != "1" ]; then
  echo ""
  echo "==> IAE curriculum_chunks ingest (grades 6–9)..."
  for grade in 6 7 8 9; do
    echo "  Grade $grade..."
    docker compose exec -T intelligent-assessment-engine \
      python scripts/ingest_and_tag_chunks.py --grade "$grade"
  done
  docker compose exec -T intelligent-assessment-engine python -c \
    "from iae.infrastructure.rag.chroma_store import ChromaChunkStore; s=ChromaChunkStore(); print('curriculum_chunks total:', s.count())"
fi

if [ "${SKIP_ANALYTICS:-0}" != "1" ]; then
  echo ""
  echo "==> Analytics Socrates RAG rebuild..."
  docker compose exec -T learner-analytics \
    python -m FastAPI-Backend.knowledge_base --rebuild
fi

echo ""
echo "Chroma ingest complete."
