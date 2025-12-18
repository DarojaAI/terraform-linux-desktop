# Terraform Infrastructure for dev-nexus

> **Infrastructure as Code** for deploying dev-nexus to Google Cloud Run

---

## Overview

This Terraform configuration deploys the complete dev-nexus infrastructure including:

- ✅ Cloud Run service with auto-scaling
- ✅ Secret Manager for credentials
- ✅ Service accounts for external agents
- ✅ IAM permissions
- ✅ Monitoring and alerting (optional)

## Prerequisites

### 1. Install Terraform

```bash
# macOS
brew install terraform

# Linux
wget https://releases.hashicorp.com/terraform/1.6.0/terraform_1.6.0_linux_amd64.zip
unzip terraform_1.6.0_linux_amd64.zip
sudo mv terraform /usr/local/bin/

# Verify installation
terraform version
```

### 2. Install gcloud CLI

```bash
# Already installed if using Cloud Shell
gcloud --version

# Otherwise: https://cloud.google.com/sdk/docs/install
```

### 3. Authenticate

```bash
# Authenticate with Google Cloud
gcloud auth login
gcloud auth application-default login

# Set project
gcloud config set project YOUR_PROJECT_ID
```

---

## Quick Start

> **⚠️ IMPORTANT:** This project uses **multi-environment Terraform** with unified initialization. Read [TERRAFORM_UNIFIED_INIT.md](../TERRAFORM_UNIFIED_INIT.md) for the recommended approach.

### Step 1: Initialize Backend (One-time)

```bash
# Set up GCS backend bucket with versioning and backups
bash scripts/setup-terraform-backend.sh
```

This creates:
- GCS bucket for state with versioning
- Backup bucket for disaster recovery
- Lifecycle policies for automatic cleanup

### Step 2: Initialize Terraform for Your Environment

```bash
# For development
bash scripts/terraform-init-unified.sh dev

# For staging
bash scripts/terraform-init-unified.sh staging

# For production
bash scripts/terraform-init-unified.sh prod
```

This automatically:
- ✅ Detects project name from directory
- ✅ Configures backend with correct bucket/prefix
- ✅ Handles reconfiguration when switching environments
- ✅ Validates configuration

### Step 3: Configure Environment Variables

```bash
# Edit the appropriate tfvars file
nano dev.tfvars      # For development
nano staging.tfvars  # For staging
nano prod.tfvars     # For production
```

Update placeholder values with actual credentials from Secret Manager:
```hcl
# Required:
github_token      = "actual-github-token"
anthropic_api_key = "actual-anthropic-key"
postgres_db_password = "actual-database-password"
```

Terraform will automatically create these as secrets in Google Secret Manager.

### Step 4: Plan Deployment

```bash
# For your chosen environment
terraform plan -var-file="dev.tfvars" -out=tfplan
```

Review the planned changes for:
- Cloud Run service
- PostgreSQL VM
- Secret Manager secrets
- VPC networking
- IAM bindings

### Step 5: Deploy

```bash
terraform apply tfplan
```

Deployment takes ~10-15 minutes (includes PostgreSQL VM provisioning).

### Step 6: Verify

```bash
# Get service URL from outputs
terraform output service_url

# Test health endpoint
SERVICE_URL=$(terraform output -raw service_url)
curl $SERVICE_URL/health

# Test AgentCard
curl $SERVICE_URL/.well-known/agent.json | jq
```

---

## Environment Configurations

For detailed environment-specific setup, see [MULTI_ENV_SETUP.md](../MULTI_ENV_SETUP.md).

### Development Environment (dev.tfvars)

**Characteristics:**
- ✅ Public access (unauthenticated)
- ✅ Scales to zero (cost-effective)
- ✅ Minimal resources (FREE tier eligible)
- ✅ Database: e2-micro, 30GB

```bash
bash scripts/terraform-init-unified.sh dev
terraform plan -var-file="dev.tfvars"
terraform apply -var-file="dev.tfvars"
```

**Cost:** ~$0-2/month (mostly free tier)

### Staging Environment (staging.tfvars)

**Characteristics:**
- ✅ Authenticated access required
- ✅ Scales to zero with moderate max
- ✅ Mid-tier resources
- ✅ Service accounts for external integrations
- ✅ Database: e2-micro, 50GB
- ✅ Monitoring enabled

```bash
bash scripts/terraform-init-unified.sh staging
terraform plan -var-file="staging.tfvars"
terraform apply -var-file="staging.tfvars"
```

**Cost:** ~$5-15/month

### Production Environment (prod.tfvars)

**Characteristics:**
- ✅ Authenticated access (strict security)
- ✅ Always-on (min 1 instance, no cold starts)
- ✅ High resources (2 vCPU, 2GB RAM)
- ✅ CPU always allocated
- ✅ Database: e2-small, 100GB
- ✅ Monitoring and alerting enabled
- ✅ Service accounts for external agents

```bash
bash scripts/terraform-init-unified.sh prod
terraform plan -var-file="prod.tfvars"
terraform apply -var-file="prod.tfvars"
```

**Cost:** ~$20-50/month (depending on traffic)

---

## Common Tasks

### Update Secrets

```bash
# Update variables in terraform.tfvars
nano terraform.tfvars

# Apply changes
terraform apply -target=google_secret_manager_secret_version.github_token
terraform apply -target=google_secret_manager_secret_version.anthropic_api_key

# Restart Cloud Run to pick up new secrets
gcloud run services update pattern-discovery-agent --region=us-central1
```

### Scale Resources

```bash
# Edit terraform.tfvars
nano terraform.tfvars

# Change:
# min_instances = 2
# max_instances = 50
# cpu = "4"
# memory = "4Gi"

# Apply
terraform apply
```

### Add Service Account

```bash
# Edit terraform.tfvars
allowed_service_accounts = [
  "existing-sa@project.iam.gserviceaccount.com",
  "new-sa@project.iam.gserviceaccount.com"  # Add this
]

# Apply
terraform apply
```

### View Outputs

```bash
# All outputs
terraform output

# Specific output
terraform output service_url
terraform output agentcard_url

# Formatted output
terraform output -json deployment_summary | jq
```

### Destroy Infrastructure

```bash
# Preview what will be deleted
terraform plan -destroy

# Destroy everything
terraform destroy
```

⚠️ **Warning:** This deletes all resources including secrets!

---

## State Management

> **Complete State Management Guide:** See [TERRAFORM_STATE_MANAGEMENT.md](../TERRAFORM_STATE_MANAGEMENT.md)

### Unified Remote State (Recommended)

All environments store state in **Google Cloud Storage** with:
- ✅ Automatic versioning for rollback
- ✅ State locking for concurrent safety
- ✅ Environment-based prefixes for isolation
- ✅ Backup bucket for disaster recovery
- ✅ Automatic lifecycle policies

**Setup (one-time):**

```bash
bash scripts/setup-terraform-backend.sh
```

This configures:
- Primary bucket: `gs://globalbiting-dev-terraform-state/`
- Environment prefixes: `dev-nexus/dev/`, `dev-nexus/staging/`, `dev-nexus/prod/`
- Backup bucket: `gs://globalbiting-dev-terraform-state-backups/`

### State Backup & Recovery

**Manual backup:**
```bash
bash scripts/backup-terraform-state.sh dev
bash scripts/backup-terraform-state.sh staging
bash scripts/backup-terraform-state.sh prod
```

**Recovery (if needed):**
```bash
bash scripts/recover-terraform-state.sh dev
```

For detailed procedures, see [TERRAFORM_STATE_MANAGEMENT.md](../TERRAFORM_STATE_MANAGEMENT.md).

---

## Troubleshooting

### Issue: "Error 403: Permission Denied"

**Cause:** Insufficient IAM permissions

**Solution:**

```bash
# Check current permissions
gcloud projects get-iam-policy YOUR_PROJECT_ID \
  --flatten="bindings[].members" \
  --filter="bindings.members:user:YOUR_EMAIL"

# Grant necessary roles
gcloud projects add-iam-policy-binding YOUR_PROJECT_ID \
  --member="user:YOUR_EMAIL" \
  --role="roles/editor"
```

### Issue: "Secret already exists"

**Cause:** Secrets created outside Terraform

**Solution:**

```bash
# Option 1: Import existing secrets
terraform import google_secret_manager_secret.github_token projects/PROJECT_ID/secrets/GITHUB_TOKEN
terraform import google_secret_manager_secret.anthropic_api_key projects/PROJECT_ID/secrets/ANTHROPIC_API_KEY

# Option 2: Delete and recreate
gcloud secrets delete GITHUB_TOKEN
gcloud secrets delete ANTHROPIC_API_KEY
terraform apply
```

### Issue: "Cloud Build failed"

**Cause:** Source code errors or missing dependencies

**Solution:**

```bash
# Check Cloud Build logs
gcloud builds list --limit=1
gcloud builds log BUILD_ID

# Test build locally
cd ..
docker build -t test-image .
```

### Issue: "State locked"

**Cause:** Previous terraform command didn't finish

**Solution:**

```bash
# Force unlock (use with caution)
terraform force-unlock LOCK_ID

# If using GCS backend, check for lock file
gsutil ls gs://your-terraform-state-bucket/dev-nexus/
```

---

## CI/CD Integration

### GitHub Actions

```yaml
# .github/workflows/terraform.yml
name: Terraform Deploy

on:
  push:
    branches: [main]
    paths:
      - 'terraform/**'

jobs:
  terraform:
    runs-on: ubuntu-latest

    steps:
      - uses: actions/checkout@v4

      - name: Setup Terraform
        uses: hashicorp/setup-terraform@v3

      - name: Authenticate to Google Cloud
        uses: google-github-actions/auth@v2
        with:
          credentials_json: ${{ secrets.GCP_SA_KEY }}

      - name: Terraform Init
        working-directory: terraform
        run: terraform init

      - name: Terraform Plan
        working-directory: terraform
        run: terraform plan

      - name: Terraform Apply
        if: github.ref == 'refs/heads/main'
        working-directory: terraform
        run: terraform apply -auto-approve
```

---

## Cost Estimation

### Terraform Managed Resources

| Resource | Cost (Monthly) | Notes |
|----------|----------------|-------|
| Cloud Run (min=0) | $0-5 | Free tier: 2M requests, 360K vCPU-s |
| Cloud Run (min=1) | $15-30 | Always-on instance |
| Secret Manager | $0 | Free tier: 10K accesses |
| Cloud Build | $0-10 | Free tier: 120 build-minutes/day |
| IAM/Service Accounts | $0 | Free |

**Total:**
- Development: $0-5/month
- Staging: $5-15/month
- Production: $20-50/month

### Estimate for Your Configuration

```bash
# Install Google Cloud Pricing Calculator
# Visit: https://cloud.google.com/products/calculator

# Or use gcloud
gcloud beta compute --project=PROJECT_ID \
  instances estimate pattern-discovery-agent \
  --region=us-central1 \
  --instance-type=n1-standard-1
```

---

## Best Practices

### 1. Use Unified Initialization Scripts

```bash
# Never use plain 'terraform init' - use the unified script
bash scripts/terraform-init-unified.sh dev    # ✅ Correct
# Don't use: terraform init                   # ❌ Wrong

# Auto-handles:
# - Backend configuration
# - Environment-specific state isolation
# - Reconfiguration when switching environments
```

### 2. Environment-Specific tfvars Files

```bash
# Each environment has its own tfvars file
terraform apply -var-file="dev.tfvars"       # ✅ Development
terraform apply -var-file="staging.tfvars"   # ✅ Staging
terraform apply -var-file="prod.tfvars"      # ✅ Production

# Never use single terraform.tfvars           # ❌ Deprecated
```

### 3. State Isolation with Prefixes

State is isolated by environment:
```
gs://globalbiting-dev-terraform-state/
├── dev-nexus/dev/       # Development
├── dev-nexus/staging/   # Staging
└── dev-nexus/prod/      # Production
```

Each environment has separate state, preventing cross-environment accidents.

### 4. Secrets Management

Never commit secrets! Terraform handles Secret Manager automatically:

```hcl
# In tfvars file (with placeholder):
github_token      = "your-actual-token"      # Replace before apply
anthropic_api_key = "your-actual-key"        # Replace before apply
postgres_db_password = "your-actual-password" # Replace before apply

# Terraform will:
# 1. Create secrets in Secret Manager (dev-nexus-{env}_* naming)
# 2. Inject into Cloud Run service
# 3. Never expose in state files
```

**Do not use environment variables:**
```bash
# ❌ Don't do this
export TF_VAR_github_token="token"
terraform apply

# ✅ Do this instead
# Edit tfvars file with real values
terraform apply -var-file="dev.tfvars"
```

### 5. Always Plan Before Apply

```bash
# Review changes before applying
terraform plan -var-file="dev.tfvars" -out=tfplan

# Show detailed plan
terraform show tfplan

# Apply only if plan looks correct
terraform apply tfplan
```

### 6. Use State Locking

State locking is **automatic** with GCS backend:
- Prevents concurrent modifications
- Safe for team collaboration
- Automatic unlock if lock expires (10 min default)

### 7. Tag Resources

```hcl
labels = {
  application = "dev-nexus"
  managed_by  = "terraform"
  environment = var.environment      # Auto-populated from tfvars
  team        = "platform"
  cost_center = "engineering"
}
```

---

## Terraform vs Bash Scripts

| Aspect | Terraform | Bash Scripts |
|--------|-----------|--------------|
| **State Management** | ✅ Built-in | ❌ Manual tracking |
| **Idempotency** | ✅ Yes | ⚠️ Depends on script |
| **Rollback** | ✅ Easy (`terraform apply` old state) | ❌ Manual |
| **Collaboration** | ✅ Remote state, locking | ❌ Difficult |
| **Validation** | ✅ `terraform validate`, `plan` | ⚠️ Manual testing |
| **Documentation** | ✅ Self-documenting | ⚠️ Comments |
| **Learning Curve** | ⚠️ Moderate | ✅ Simple |

**Recommendation:** Use Terraform for production, bash scripts for quick tests.

---

## Documentation

### Multi-Environment Setup
- [TERRAFORM_UNIFIED_INIT.md](../TERRAFORM_UNIFIED_INIT.md) - Unified initialization across projects
- [MULTI_ENV_SETUP.md](../MULTI_ENV_SETUP.md) - Environment-specific configuration and deployment
- [TERRAFORM_STATE_MANAGEMENT.md](../TERRAFORM_STATE_MANAGEMENT.md) - State backup and recovery

### Deployment
- [DEPLOYMENT.md](../DEPLOYMENT.md) - Quick deployment guide (bash scripts alternative)
- [DEPLOYMENT_READINESS.md](../DEPLOYMENT_READINESS.md) - Pre-deployment checklist

### Reference
- [CLAUDE.md](../CLAUDE.md) - Developer guidelines (includes multi-environment section)

### External References
- Terraform: https://registry.terraform.io/providers/hashicorp/google/latest/docs
- Cloud Run: https://cloud.google.com/run/docs
- Google Secret Manager: https://cloud.google.com/secret-manager

## Issues

**GitHub:** https://github.com/patelmm79/dev-nexus/issues

---

**Last Updated:** 2025-12-18
**Version:** 2.0
**Key Changes:**
- ✅ Multi-environment setup with dev/staging/prod
- ✅ Unified terraform-init-unified.sh scripts
- ✅ Remote state management with versioning
- ✅ State backup and recovery procedures
- ✅ Environment-specific tfvars files
- ✅ Automatic Secret Manager integration
