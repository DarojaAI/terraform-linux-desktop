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

### Step 1: Configure Variables

```bash
# Copy example configuration
cp terraform.tfvars.example terraform.tfvars

# Edit with your values
nano terraform.tfvars
```

**Required values:**
```hcl
project_id          = "your-gcp-project-id"
github_token        = "ghp_xxxxxxxxxxxxx"
anthropic_api_key   = "sk-ant-xxxxxxxxxxxxx"
knowledge_base_repo = "username/repository"
```

### Step 2: Initialize Terraform

```bash
terraform init
```

Expected output:
```
Initializing the backend...
Initializing provider plugins...
- Finding hashicorp/google versions matching "~> 5.0"...
- Installing hashicorp/google v5.x.x...

Terraform has been successfully initialized!
```

### Step 3: Plan Deployment

```bash
terraform plan
```

Review the planned changes. You should see:
- Secret Manager secrets (2)
- Cloud Run service (1)
- IAM bindings (~4)
- Service accounts (if enabled)

### Step 4: Deploy

```bash
terraform apply
```

Type `yes` when prompted.

Deployment takes ~5-10 minutes.

### Step 5: Verify

```bash
# Get service URL from outputs
SERVICE_URL=$(terraform output -raw service_url)

# Test health endpoint
curl $SERVICE_URL/health

# Test AgentCard
curl $SERVICE_URL/.well-known/agent.json | jq
```

---

## Configuration Options

### Development Environment

**Characteristics:**
- Public access (no authentication)
- Scales to zero
- Minimal resources

```hcl
# terraform.tfvars
allow_unauthenticated = true
min_instances         = 0
max_instances         = 5
cpu                   = "1"
memory                = "1Gi"
```

**Cost:** ~$0-2/month (mostly free tier)

### Staging Environment

**Characteristics:**
- Private access (authentication required)
- Scales to zero
- Moderate resources
- Service accounts for external agents

```hcl
# terraform.tfvars
allow_unauthenticated            = false
min_instances                    = 0
max_instances                    = 10
cpu                              = "1"
memory                           = "2Gi"
create_external_service_accounts = true
allowed_service_accounts = [
  "log-attacker@project.iam.gserviceaccount.com",
  "orchestrator@project.iam.gserviceaccount.com"
]
```

**Cost:** ~$2-10/month

### Production Environment

**Characteristics:**
- Private access
- Always-on (no cold starts)
- High resources
- Monitoring and alerts enabled

```hcl
# terraform.tfvars
allow_unauthenticated            = false
min_instances                    = 1     # Always warm
max_instances                    = 20    # Handle traffic spikes
cpu                              = "2"
memory                           = "2Gi"
cpu_always_allocated             = true  # No cold starts
create_external_service_accounts = true
enable_monitoring_alerts         = true
error_rate_threshold             = 5.0
latency_threshold_ms             = 3000

# Service accounts with proper scoping
allowed_service_accounts = [
  "log-attacker-prod@project.iam.gserviceaccount.com",
  "orchestrator-prod@project.iam.gserviceaccount.com"
]
```

**Cost:** ~$15-50/month (depending on traffic)

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

### Local State (Default)

By default, Terraform stores state locally in `terraform.tfstate`.

**Pros:**
- Simple
- No setup required

**Cons:**
- Not collaborative
- No backup
- State can be lost

### Remote State (Recommended for Teams)

Store state in Google Cloud Storage for collaboration and safety.

**Setup:**

```bash
# Create bucket for state
gsutil mb gs://your-terraform-state-bucket

# Enable versioning (for rollback)
gsutil versioning set on gs://your-terraform-state-bucket
```

**Configure backend in main.tf:**

```hcl
terraform {
  backend "gcs" {
    bucket = "your-terraform-state-bucket"
    prefix = "dev-nexus"
  }
}
```

**Migrate existing state:**

```bash
terraform init -migrate-state
```

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

### 1. Use Workspaces for Environments

```bash
# Create workspaces
terraform workspace new dev
terraform workspace new staging
terraform workspace new production

# Switch between environments
terraform workspace select production
terraform apply -var-file=production.tfvars
```

### 2. Tag Resources

```hcl
labels = {
  environment = "production"
  managed_by  = "terraform"
  team        = "platform"
  cost_center = "engineering"
}
```

### 3. Enable State Locking

Using GCS backend enables automatic state locking.

### 4. Use Variables for Secrets

Never commit secrets to git!

```bash
# Use environment variables
export TF_VAR_github_token="ghp_xxxxx"
export TF_VAR_anthropic_api_key="sk-ant-xxxxx"

# Terraform will use these automatically
terraform apply
```

### 5. Plan Before Apply

```bash
# Always review changes
terraform plan -out=tfplan

# Apply only if plan looks good
terraform apply tfplan
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

## Support

**Documentation:**
- Terraform: https://registry.terraform.io/providers/hashicorp/google/latest/docs
- Cloud Run: https://cloud.google.com/run/docs

**Issues:**
- GitHub: https://github.com/patelmm79/dev-nexus/issues

---

**Last Updated:** 2025-12-09
**Version:** 1.0
