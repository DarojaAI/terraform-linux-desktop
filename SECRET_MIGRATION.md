# Secret Naming Migration Guide

**Date:** 2026-05-03
**Type:** Breaking Change
**Impact:** All existing deployments must migrate to new secret naming convention

---

## Summary

The secret naming convention in Terraform was updated to align with the Phase 5 Secrets Contract (`PHASE_5_SECRETS.md`).

**Old convention (underscore-based, mixed case):**
```
dev-nexus-prod_POSTGRES_PASSWORD
dev-nexus-prod_GITHUB_TOKEN
dev-nexus-prod_ANTHROPIC_API_KEY
```

**New convention (hyphen-based, all lowercase):**
```
dev-nexus-prod-postgres-password
dev-nexus-prod-github-token
dev-nexus-prod-anthropic-api-key
```

---

## Why This Change?

1. **Contract Alignment** — The Phase 5 Secrets Contract specifies all-lowercase hyphenated names
2. **GCP Best Practices** — GCP Secret Manager recommends lowercase hyphenated names for consistency
3. **Predictability** — Secret names are now fully derivable from environment and purpose
4. **Consistency** — All secret names follow the same `{prefix}-{name}` pattern

---

## Breaking Change Impact

⚠️ **This is a breaking change.** When you apply this Terraform update:

1. **New secrets will be created** with the new naming convention
2. **Old secrets will become orphaned** (still exist in GCP, but no longer managed by Terraform)
3. **Cloud Run will use the new secrets** after the next successful `terraform apply`
4. **Old secrets must be manually cleaned up** after verifying the new ones work

---

## Migration Steps for Existing Deployments

### Step 1: Backup Current State (Optional but Recommended)

```bash
# Create a backup of your current Terraform state
cd terraform
terraform state pull > terraform-state-backup-$(date +%Y%m%d).json
```

### Step 2: Update Terraform Code

```bash
# Pull the latest changes that include the new naming
git pull origin main

# Navigate to terraform directory
cd terraform

# Re-initialize if needed (terraform init with existing backend)
bash scripts/terraform-init-unified.sh <your-environment>
```

### Step 3: Plan the Changes

```bash
# Review what Terraform will do
terraform plan -var-file="<your-env>.tfvars" -out=tfplan

# Look for:
# - Creation of new secrets (with new naming)
# - No destruction of old secrets (Terraform loses track of them)
```

### Step 4: Apply the Changes

```bash
terraform apply tfplan
```

After apply:
- New secrets are created in Secret Manager with the correct naming
- Cloud Run service is updated to reference the new secret names
- Old secrets remain in GCP (orphaned)

### Step 5: Verify the New Secrets Work

```bash
# Check that new secrets exist
gcloud secrets list --project=globalbiting-dev --filter="dev-nexus-<env>-"

# Verify Cloud Run is using new secrets
gcloud run services describe pattern-discovery-agent \
  --region=us-central1 \
  --format="value(spec.template.spec.containers[0].env[].name)"

# Test the service health
SERVICE_URL=$(gcloud run services describe pattern-discovery-agent \
  --region=us-central1 \
  --format="value(status.url)")
curl $SERVICE_URL/health
```

### Step 6: Clean Up Old Secrets (After Verification)

⚠️ **Only do this after verifying the new secrets work correctly.**

```bash
# List old secrets (underscore-based naming)
gcloud secrets list --project=globalbiting-dev \
  --filter="name:dev-nexus-<env>_"

# Delete old secrets (example for prod environment)
gcloud secrets delete dev-nexus-prod_POSTGRES_PASSWORD --project=globalbiting-dev
gcloud secrets delete dev-nexus-prod_POSTGRES_USER --project=globalbiting-dev
gcloud secrets delete dev-nexus-prod_POSTGRES_DB --project=globalbiting-dev
gcloud secrets delete dev-nexus-prod_POSTGRES_HOST --project=globalbiting-dev
gcloud secrets delete dev-nexus-prod_GITHUB_TOKEN --project=globalbiting-dev
gcloud secrets delete dev-nexus-prod_GITHUB_CLIENT_ID --project=globalbiting-dev
gcloud secrets delete dev-nexus-prod_GITHUB_CLIENT_SECRET --project=globalbiting-dev
gcloud secrets delete dev-nexus-prod_JWT_SECRET --project=globalbiting-dev
gcloud secrets delete dev-nexus-prod_ANTHROPIC_API_KEY --project=globalbiting-dev
gcloud secrets delete dev-nexus-prod_LANGSMITH_API_KEY --project=globalbiting-dev
gcloud secrets delete dev-nexus-prod_PATTERN_MINER_TOKEN --project=globalbiting-dev
gcloud secrets delete dev-nexus-prod_ACTION_AGENT_TOKEN --project=globalbiting-dev
gcloud secrets delete dev-nexus-prod_ORCHESTRATOR_TOKEN --project=globalbiting-dev
```

**Alternative: Use a script to find and delete all old-format secrets:**
```bash
# List all old-format secrets
gcloud secrets list --project=globalbiting-dev --format="value(name)" \
  | grep "dev-nexus-.*_" \
  | while read secret; do
      echo "Would delete: $secret"
      # Uncomment to actually delete:
      # gcloud secrets delete "$secret" --project=globalbiting-dev
  done
```

---

## New Secret Names Reference

| Secret Purpose | Old Name (Orphaned) | New Name (Active) |
|----------------|----------------------|-------------------|
| PostgreSQL Password | `dev-nexus-{env}_POSTGRES_PASSWORD` | `dev-nexus-{env}-postgres-password` |
| PostgreSQL User | `dev-nexus-{env}_POSTGRES_USER` | `dev-nexus-{env}-postgres-user` |
| PostgreSQL DB | `dev-nexus-{env}_POSTGRES_DB` | `dev-nexus-{env}-postgres-db` |
| PostgreSQL Host | `dev-nexus-{env}_POSTGRES_HOST` | `dev-nexus-{env}-postgres-host` |
| GitHub Token | `dev-nexus-{env}_GITHUB_TOKEN` | `dev-nexus-{env}-github-token` |
| GitHub Client ID | `dev-nexus-{env}_GITHUB_CLIENT_ID` | `dev-nexus-{env}-github-client-id` |
| GitHub Client Secret | `dev-nexus-{env}_GITHUB_CLIENT_SECRET` | `dev-nexus-{env}-github-client-secret` |
| JWT Secret | `dev-nexus-{env}_JWT_SECRET` | `dev-nexus-{env}-jwt-secret` |
| Anthropic API Key | `dev-nexus-{env}_ANTHROPIC_API_KEY` | `dev-nexus-{env}-anthropic-api-key` |
| LangSmith API Key | `dev-nexus-{env}_LANGSMITH_API_KEY` | `dev-nexus-{env}-langsmith-api-key` |
| Pattern Miner Token | `dev-nexus-{env}_PATTERN_MINER_TOKEN` | `dev-nexus-{env}-pattern-miner-token` |
| Action Agent Token | `dev-nexus-{env}_ACTION_AGENT_TOKEN` | `dev-nexus-{env}-action-agent-token` |
| Orchestrator Token | `dev-nexus-{env}_ORCHESTRATOR_TOKEN` | `dev-nexus-{env}-orchestrator-token` |

---

## FAQ

### Q: Will my application go down during migration?
**A:** No. The migration creates new secrets and updates Cloud Run to use them. There may be a brief single Pod restart during the Cloud Run update.

### Q: Can I rollback if something goes wrong?
**A:** Yes. The old secrets still exist (orphaned) with their values intact. You can revert the Terraform code and re-apply to switch back.

### Q: Do I need to update my GitHub Actions workflows?
**A:** No. The GitHub Actions workflows set `TF_VAR_*` environment variables — these are still the same. Only the GCP Secret Manager names changed.

### Q: How do I know if I'm affected?
**A:** If you deployed before 2026-05-03, you have the old-format secrets. Check with:
```bash
gcloud secrets list --project=globalbiting-dev --filter="name:dev-nexus-.*_"
```

### Q: Can I skip the old secret cleanup?
**A:** It's recommended to clean up to avoid confusion and potential security issues (secrets with old values lingering). However, it's not technically required for operation.

---

## Verification Script

```bash
#!/bin/bash
# verify-migration.sh — Run after migration to verify success

PROJECT_ID="globalbiting-dev"
ENV="prod"  # or "dev", "staging"

echo "=== Checking for new-format secrets ==="
gcloud secrets list --project=$PROJECT_ID --format="value(name)" \
  | grep "dev-nexus-$ENV-" \
  | sort

echo ""
echo "=== Checking for old-format secrets (should be empty after cleanup) ==="
gcloud secrets list --project=$PROJECT_ID --format="value(name)" \
  | grep "dev-nexus-$ENV_" || echo "None found (good!)"

echo ""
echo "=== Verifying Cloud Run uses new secret names ==="
gcloud run services describe pattern-discovery-agent \
  --region=us-central1 \
  --format="value(spec.template.spec.containers[0].env[].valueSource.secretKeyRef.secret)"
```

---

**Last Updated:** 2026-05-03
