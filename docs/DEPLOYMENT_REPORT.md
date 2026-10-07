# SCI-PATH Deployment Report

**Project:** SCI-PATH — System for Science Pathways  
**Report date:** 29 August 2026  
**Purpose:** Evaluation evidence — cloud deployment, CI/CD, and operational status  
**Region:** AWS `ap-southeast-2` (Sydney). Account `569757034406`.

---

## 1. Executive summary

SCI-PATH is deployed as a **multi-service, multi-EC2** system: five backend microservices, one Next.js frontend, shared **Neon PostgreSQL**, and **ChromaDB** vector stores per service. Images are built in GitHub Actions, pushed to **Amazon ECR**, and pulled onto EC2 instances via Docker Compose. Boot-time systemd units re-deploy on instance restart.

As of this report:

| Area | Status |
|------|--------|
| Core EC2 (LPE, UM, Gaming) | **Operational** — HTTP 200 on health checks |
| Analytics EC2 | **Operational** — HTTP 200 |
| IAE EC2 (Assessment / Aptitude) | **Down** — port 8004 connection refused (container not listening) |
| Verified lesson content (Neon) | **Complete** — 192/192 rows (G6–G9 × basic/intermediate/advanced) |
| Reference sheets (Neon) | **Complete** — 64/64 chapters |
| Frontend (local dev → EC2 APIs) | Configured via `.env.local` pointing at Elastic IPs |

---

## 2. System architecture

```
┌─────────────────────────────────────────────────────────────────┐
│  frontend-app (Next.js :3000)                                    │
│  Rewrites: /user-api → UM | /assessment-api → IAE | LPE paths   │
└──────┬────────────┬─────────────┬──────────────┬─────────────────┘
       │            │             │              │
       ▼            ▼             ▼              ▼
  54.253.38.67 54.253.38.67  54.253.38.67 54.253.36.7      3.104.28.68
  :8001 UM     :8000 LPE     :8002 Gaming  :8003 Analytics  :8004 IAE
       │            │             │              │              │
       └────────────┴─────────────┴──────────────┴──────────────┘
                              │
                    Neon PostgreSQL (shared cloud DB)
                    Schemas: shared, content_generation, question_engine,
                             learner_analytics, engagement_gaming
```

### Component ownership (team)

| Component | Owner (proposal) | Repo | Port | DB schema |
|-----------|------------------|------|------|-----------|
| Learning Path Engine (C1) | Piyaratne U.A.D.T. | `learning-path-engine` | 8000 | `content_generation` |
| User Management | — | `user-management` | 8001 | `shared` |
| Gaming / Engagement (C3) | Pieris P.S.G. | `gaming-service` | 8002 | `engagement_gaming` |
| Learner Analytics (C4) | Liyaudeen D.H. | `learner-analytics-genai-support` | 8003 | `learner_analytics` |
| Intelligent Assessment (C2) | Amaratunga Y.B. | `intelligent-assessment-engine` | 8004 | `question_engine` |
| Frontend | Shared | `frontend-app` | 3000 | — |

---

## 3. AWS infrastructure

### 3.1 EC2 instances (Elastic IPs)

| Role | Public IP | Compose profile | Services / ports |
|------|-----------|-----------------|----------------|
| **Core** | `54.253.38.67` | `core` | LPE 8000, UM 8001, Gaming 8002 |
| **Analytics** | `54.253.36.7` | `analytics` | Analytics 8003 |
| **IAE** | `3.104.28.68` | `iae` | Assessment Engine 8004 |

**Host path on each box:** `/opt/sci-path/deployment-orchestration`

**Boot service:** `sci-path-boot.service` — runs `scripts/ec2/deploy.sh all` after reboot (20s delay for Docker/network).

### 3.2 Container registry (ECR)

Registry: `569757034406.dkr.ecr.ap-southeast-2.amazonaws.com/sci-path/`

| Image | Tag strategy |
|-------|----------------|
| `lpe` | `:latest` + `:sha` |
| `um` | `:latest` + `:sha` |
| `gaming` | `:latest` + `:sha` |
| `analytics` | `:latest` + `:sha` |
| `iae` | `:latest` + `:sha` |

### 3.3 Database

- **Provider:** Neon PostgreSQL (serverless, `us-east-2`)
- **Database name:** `neondb`
- **Usage:** Shared across UM, LPE content library, IAE question bank, analytics events, gaming state
- **Schemas:** Isolated per component; migrations are idempotent (no destructive auto-drops on IAE)

### 3.4 Other AWS

- **S3:** `sci-path-demo-assets-dhanu` (lesson media, AR assets) — region `ap-southeast-2`
- **Security groups:** Inbound TCP **8000–8004** (and 22 for SSH) from team/demo IPs

---

## 4. CI/CD pipeline

**Orchestration repo:** `SCI-PATH/deployment-orchestration`  
**Workflow:** `.github/workflows/ci-deploy.yml` (`sci-path-deploy`)

### 4.1 Trigger flow

```
Push to service repo (dev/main)
  → repository_dispatch to deployment-orchestration
  → Parallel Docker builds (5 jobs, one per service)
  → Push to ECR (:latest + commit SHA)
  → SSH deploy to target EC2:
       core      → EC2_HOST_CORE (or EC2_HOST)
       analytics → EC2_HOST_ANALYTICS
       iae       → EC2_HOST_IAE
  → deploy.sh: stop → remove old images → pull :latest → docker compose up -d
```

### 4.2 Deploy script hardening (Aug 2026)

`scripts/ec2/deploy.sh` improvements for production stability:

- **Disk guard:** Abort pull if root filesystem &lt; 8 GB free
- **Image refresh:** `docker compose down --rmi all` before pull — avoids old+new images filling disk
- **Post-deploy prune:** `docker image prune -af`
- **CRLF fix:** Line-ending normalization for shell scripts on Windows-authored commits

### 4.3 GitHub Actions secrets (required)

| Secret | Purpose |
|--------|---------|
| `AWS_ACCESS_KEY_ID` / `AWS_SECRET_ACCESS_KEY` | ECR push |
| `EC2_HOST`, `EC2_HOST_CORE`, `EC2_HOST_ANALYTICS`, `EC2_HOST_IAE` | Deploy targets |
| `EC2_SSH_KEY` | SSH private key (`sci-path-demo2.pem`) |
| `SUBMODULES_ACCESS_TOKEN` | Private submodule checkout |

---

## 5. Deployment procedures (manual)

### 5.1 Full redeploy on an EC2 box (SSH)

```bash
ssh -i sci-path-demo2.pem ubuntu@<ELASTIC_IP>
cd /opt/sci-path/deployment-orchestration
bash scripts/ec2/deploy.sh all      # or: core | analytics | iae
docker compose --profile <profile> ps
curl -s http://127.0.0.1:<port>/health
```

### 5.2 Frontend (developer machine → cloud APIs)

File: `frontend-app/.env.local`

```env
API_PROXY_TARGET=http://54.253.38.67:8000
USER_API_PROXY_TARGET=http://54.253.38.67:8001
GAMING_API_PROXY_TARGET=http://54.253.38.67:8002
ASSESSMENT_API_PROXY_TARGET=http://3.104.28.68:8004
NEXT_PUBLIC_API_URL=http://54.253.36.7:8003
NEXT_PUBLIC_IAE_API_BASE=http://3.104.28.68:8004
```

Run: `npm run dev` (port 3000). Restart dev server after env changes.

### 5.3 Chroma textbook ingest (one-time / after PDF update)

```bash
# On host with Docker compose
./scripts/ingest-chromas.sh    # LPE + IAE + Analytics
```

---

## 6. Content & data deployment (Component 1 evidence)

### 6.1 Verified lesson content

**Table:** `content_generation.verified_lesson_content`  
**Scope:** Sri Lankan science curriculum, Grades 6–9, three learner profiles per lesson.

| Grade | Lessons | Profiles each | Rows |
|-------|---------|---------------|------|
| 6 | 11 | 3 | 33 |
| 7 | 19 | 3 | 57 |
| 8 | 15 | 3 | 45 |
| 9 | 19 | 3 | 57 |
| **Total** | **64** | **3** | **192** |

**Generation methods used:**

1. **Groq LLM** (via LPE `build_lesson` pipeline) — demo path; `teacher_id = bulk-script`
2. **Local/Cursor generation** (passage-grounded, no Groq) — bulk fill when Groq daily token limit hit; `teacher_id = cursor-local`

**Audit command:**

```bash
cd learning-path-engine/backend
.\.venv\Scripts\python.exe scripts/bulk_publish_verified_content.py --audit
```

**Result (29 Aug 2026):** `192/192 present, 0 missing`

### 6.2 Reference sheets (student revision notes)

**Storage:** `lesson_media.cheatsheet_json` (UI label: **Reference sheet**)  
**Scope:** One sheet per chapter (64 lessons)  
**Result (29 Aug 2026):** `64/64 present`  
**Generation:** Local batch from Chroma passages (`import_reference_sheets.py`), source tag `cursor-local`

### 6.3 Teacher demo path (Groq live generation)

Unchanged for evaluation demos:

- `POST /teacher/generate` → Chroma retrieval + Groq LLM
- `POST /teacher/library` → upsert to Neon
- Bulk script: `scripts/bulk_publish_verified_content.py --generate`

Groq free tier: ~200k tokens/day (resets on rolling 24h window).

---

## 7. Health checks (Sydney)

```bash
curl -s http://54.253.38.67:8000/health
curl -s http://54.253.38.67:8001/health
curl -s http://54.253.38.67:8002/api/health
curl -s http://54.253.36.7:8003/health
curl -s http://3.104.28.68:8004/
```

If IAE does not answer:

```bash
ssh -i sci-path-demo2.pem ubuntu@3.104.28.68
docker ps -a | grep iae
docker logs sci-path-iae --tail 100
cd /opt/sci-path/deployment-orchestration && bash scripts/ec2/deploy.sh iae
```

---

## 8. Known issues & mitigations

| Issue | Mitigation |
|-------|------------|
| Analytics EC2 disk full during Docker pull | CPU-only torch in analytics Dockerfile; deploy.sh prune + disk check |
| Groq rate limits for bulk content | Local generation pipeline + import scripts |
| IAE down after teammate deploy / reboot | Verify `COMPOSE_PROFILES=iae`, boot service, container logs |
| CRLF in `deploy.sh` on Linux | `.gitattributes` + CI `sed` strip |
| SonarCloud | Pilot config added; org Admin role needed to import projects |

---

## 9. Repository map (deployment-related)

| Repository | Role |
|------------|------|
| `deployment-orchestration` | Docker Compose, CI/CD, EC2 scripts, boot unit |
| `learning-path-engine` | C1 API, content scripts, Chroma ingest |
| `intelligent-assessment-engine` | C2 API, amplitude/quiz bank |
| `learner-analytics-genai-support` | C4 API |
| `gaming-service` | C3 API |
| `user-management` | Auth, users, classes |
| `frontend-app` | Next.js UI, API rewrites |
| `tests` | Integration / E2E test suite (`SCI-PATH/tests`) |

---

## 10. Evaluation evidence checklist

Attach or screenshot the following for assessors:

- [ ] **Architecture diagram** — Section 2 above or `sci_path_system_overview.md`
- [ ] **GitHub Actions** — Successful `sci-path-deploy` workflow run (build + push + SSH deploy)
- [ ] **ECR** — Five `sci-path/*` repositories with recent `:latest` pushes
- [ ] **EC2** — `docker compose ps` on core / analytics / IAE boxes
- [ ] **Health checks** — curl/browser: LPE `/health`, Analytics `/health`, IAE `/docs`
- [ ] **Neon** — Row counts: 192 verified lessons; 64 reference sheets
- [ ] **Frontend** — Student lesson flow (Arthur mascot, reference sheet tab, stepped slides)
- [ ] **Teacher demo** — Groq live generation via Teacher Panel (when credits available)
- [ ] **Aptitude test** — Amplitude survey + quiz (requires IAE up)
- [ ] **Boot persistence** — `systemctl status sci-path-boot` after EC2 reboot

---

## 11. Sign-off

| Item | Detail |
|------|--------|
| Deployment model | Docker on AWS EC2 + ECR + GitHub Actions |
| Environments | Demo/production-like EC2 (no separate staging URL) |
| Data | Neon PostgreSQL + per-service Chroma volumes |
| Content readiness | Full G6–G9 verified lessons + reference sheets |
| Blocker for full E2E demo | IAE service on `3.104.28.68:8004` must be up |

---

*Generated for SCI-PATH team evaluation. Update health-check table after IAE recovery.*
