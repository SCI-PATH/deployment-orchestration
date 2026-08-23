# ECR + auto-deploy pipeline

Push to a service repo (`dev`/`main`/`develop`) → orchestration CI builds → pushes to **ECR** → SSHs to EC2 → `docker compose pull` + restart.

```
service repo push
  → trigger-orchestration.yml (repository_dispatch)
  → deployment-orchestration ci-deploy.yml
  → build sci-path-*:ci
  → push 011877215030.dkr.ecr.ap-south-1.amazonaws.com/sci-path/{lpe|um|gaming|analytics|iae}:latest (+ :sha)
  → ssh ubuntu@EC2_HOST 'bash scripts/ec2/deploy.sh <service>'
```

## ECR repositories (already created)

| Service | ECR repo URI |
|---------|----------------|
| LPE | `011877215030.dkr.ecr.ap-south-1.amazonaws.com/sci-path/lpe` |
| UM | `.../sci-path/um` |
| Gaming | `.../sci-path/gaming` |
| Analytics | `.../sci-path/analytics` |
| IAE | `.../sci-path/iae` |

## 1. GitHub secrets (`SCI-PATH/deployment-orchestration`)

Repo → **Settings** → **Secrets and variables** → **Actions** → add:

| Secret | Value |
|--------|--------|
| `SUBMODULES_ACCESS_TOKEN` | PAT with `repo` (read private service repos) |
| `AWS_ACCESS_KEY_ID` | IAM user access key (ECR push) |
| `AWS_SECRET_ACCESS_KEY` | IAM secret |
| `AWS_REGION` | `ap-south-1` (optional if you rely on workflow default) |
| `EC2_HOST` | `3.6.20.31` (Elastic IP) |
| `EC2_SSH_KEY` | Full contents of `sci-path-demo.pem` (including `BEGIN/END` lines) |
| `EC2_USER` | `ubuntu` (optional) |

### IAM policy for the CI user (minimum)

Allow ECR push/pull on `sci-path/*` and `ecr:GetAuthorizationToken`. Example:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": ["ecr:GetAuthorizationToken"],
      "Resource": "*"
    },
    {
      "Effect": "Allow",
      "Action": [
        "ecr:BatchCheckLayerAvailability",
        "ecr:GetDownloadUrlForLayer",
        "ecr:BatchGetImage",
        "ecr:PutImage",
        "ecr:InitiateLayerUpload",
        "ecr:UploadLayerPart",
        "ecr:CompleteLayerUpload",
        "ecr:DescribeRepositories"
      ],
      "Resource": "arn:aws:ecr:ap-south-1:011877215030:repository/sci-path/*"
    }
  ]
}
```

## 2. EC2 setup (pull from ECR)

SSH to the instance, then:

```bash
# AWS CLI (once)
sudo apt-get update -qq
sudo apt-get install -y awscli

# Credentials: either attach an IAM instance role with ECR pull,
# or configure the same IAM user:
aws configure
# AWS Access Key ID / Secret / region ap-south-1
```

In `/opt/sci-path/deployment-orchestration/.env`, set:

```env
AWS_REGION=ap-south-1
ECR_REGISTRY=011877215030.dkr.ecr.ap-south-1.amazonaws.com
IMAGE_LPE=011877215030.dkr.ecr.ap-south-1.amazonaws.com/sci-path/lpe:latest
IMAGE_UM=011877215030.dkr.ecr.ap-south-1.amazonaws.com/sci-path/um:latest
IMAGE_GAMING=011877215030.dkr.ecr.ap-south-1.amazonaws.com/sci-path/gaming:latest
IMAGE_ANALYTICS=011877215030.dkr.ecr.ap-south-1.amazonaws.com/sci-path/analytics:latest
IMAGE_IAE=011877215030.dkr.ecr.ap-south-1.amazonaws.com/sci-path/iae:latest
```

Pull orchestration changes (after this PR is on `main`):

```bash
cd /opt/sci-path/deployment-orchestration
git pull --ff-only
```

Manual pull/restart:

```bash
bash scripts/ec2/deploy.sh all
# or: bash scripts/ec2/deploy.sh gaming
```

### Switch EC2 from local build → ECR pull (wipe local images)

After ECR has images (CI workflow or manual push):

```bash
cd /opt/sci-path/deployment-orchestration
git pull --ff-only
bash scripts/ec2/switch-to-ecr-pull.sh
```

Shows `df -h` before/after so you can see how much disk pull-only needs.
Dry run: `bash scripts/ec2/switch-to-ecr-pull.sh --dry-run`

## 3. First seed (optional — if EC2 already built `:local` images)

From **EC2**, after AWS CLI login works:

```bash
cd /opt/sci-path/deployment-orchestration
source .env
aws ecr get-login-password --region ap-south-1 \
  | docker login --username AWS --password-stdin "$ECR_REGISTRY"

REG=011877215030.dkr.ecr.ap-south-1.amazonaws.com

docker tag sci-path-lpe:local        $REG/sci-path/lpe:latest
docker tag sci-path-um:local         $REG/sci-path/um:latest
docker tag sci-path-gaming:local     $REG/sci-path/gaming:latest
docker tag sci-path-analytics:local  $REG/sci-path/analytics:latest
docker tag sci-path-iae:local        $REG/sci-path/iae:latest

docker push $REG/sci-path/lpe:latest
docker push $REG/sci-path/um:latest
docker push $REG/sci-path/gaming:latest
docker push $REG/sci-path/analytics:latest
docker push $REG/sci-path/iae:latest
```

Or skip seeding and run **Actions → sci-path-deploy → Run workflow → all** once secrets are set.

## 4. Test end-to-end

1. Add all GitHub secrets above.
2. Uncomment `IMAGE_*` on EC2 `.env`.
3. Push a tiny change to e.g. `gaming-service` `main`/`dev`, **or** run workflow_dispatch for `gaming`.
4. Watch `deployment-orchestration` Actions: build → ECR push → EC2 deploy.
5. Check: `curl http://3.6.20.31:8002/api/health`

## Local vs EC2 images

| Environment | `IMAGE_*` in `.env` | How images are created |
|-------------|---------------------|-------------------------|
| Your PC | unset (defaults `sci-path-*:local`) | `docker compose up -d --build` |
| EC2 | full ECR URIs | CI push + `deploy.sh` pull |

Compose keeps `build:` contexts so local rebuilds still work when `IMAGE_*` is unset.
