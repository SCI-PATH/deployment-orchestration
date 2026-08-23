# Stable EC2 address (Elastic IP)

Default EC2 public IPs **change after Stop → Start**. An **Elastic IP** stays fixed.

You already have: 1 EC2 + 5 ECR repos + S3. Do this **before** first deploy.

## Option A — AWS Console (recommended if no AWS CLI)

1. Open **EC2** → left menu **Elastic IPs**  
   (or search “Elastic IP” in the AWS console top bar)
2. Click **Allocate Elastic IP address**
3. Leave defaults (**Amazon’s pool of IPv4** / VPC) → **Allocate**
4. Select the new Elastic IP → **Actions** → **Associate Elastic IP address**
5. **Instance** → pick your SCI-PATH EC2 → **Associate**
6. Copy the **Public IPv4 address** shown (e.g. `54.x.x.x`)

That IP is now your stable host. Stop/start the instance and it stays the same.

### Security group (needed so services are reachable)

EC2 → Instances → your instance → **Security** → security group → **Edit inbound rules**  
Add (for a college demo you can allow from anywhere; tighten later):

| Type | Port | Source |
|------|------|--------|
| SSH | 22 | My IP (or yours) |
| Custom TCP | 8000–8004 | `0.0.0.0/0` (or My IP only) |
| Custom TCP | 3000 | optional if Next runs on EC2 |

### Save the IP in env

In `deployment-orchestration/.env` (on your PC and later on the server):

```env
EC2_HOST=54.x.x.x
IAE_API_BASE_URL=http://54.x.x.x:8004
CORS_ORIGINS=http://localhost:3000,http://127.0.0.1:3000
```

Frontend (when you deploy Next / local `.env.local`):

```env
API_PROXY_TARGET=http://54.x.x.x:8000
USER_API_PROXY_TARGET=http://54.x.x.x:8001
ASSESSMENT_API_PROXY_TARGET=http://54.x.x.x:8004
NEXT_PUBLIC_API_URL=http://54.x.x.x:8003
```

Service map on that one IP:

| Port | Service |
|------|---------|
| 8000 | Learning Path Engine |
| 8001 | User Management |
| 8002 | Gaming |
| 8003 | Analytics |
| 8004 | IAE (Assessment) |

## Option B — AWS CLI (after `aws` is installed)

On a machine with AWS CLI configured:

```bash
cd deployment-orchestration
bash scripts/ec2/allocate-elastic-ip.sh
# or: bash scripts/ec2/allocate-elastic-ip.sh i-0yourInstanceId
```

Windows PowerShell:

```powershell
cd deployment-orchestration
.\scripts\ec2\allocate-elastic-ip.ps1
```

## Cost note

- Elastic IP is **free** while associated with a **running** instance.
- You may be charged if the EIP is allocated but **not** attached, or attached to a **stopped** instance for a long time.
- If you delete the EC2 forever: **Release** the Elastic IP so you are not billed.

## After EIP is set

Continue with:

1. `scripts/ec2/bootstrap.sh` on the instance (Docker + clone)
2. Fill `.env` with Neon, Groq, `EC2_HOST`, CORS, and (for ECR pulls) `IMAGE_*` URIs — see [ecr-pipeline.md](./ecr-pipeline.md)
3. First boot: `docker compose up -d --build` **or** pull from ECR via `scripts/ec2/deploy.sh all`
4. One-time Chroma ingest: `scripts/ingest-chromas.sh`
5. Wire GitHub → ECR → EC2 auto-deploy: [ecr-pipeline.md](./ecr-pipeline.md)

