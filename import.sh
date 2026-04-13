#!/bin/bash
# Terraform Import Script
# Imports existing GCP resources into terraform state.
# Usage: ./import.sh <environment>   e.g., ./import.sh prod
#
# Add new resources to the IMPORTS array below.
# The script reads secret_prefix and project_id from the target .tfvars file.

set -e

ENV="${1:-}"
if [[ -z "$ENV" ]]; then
  echo "Usage: $0 <environment>   (e.g., $0 prod)"
  echo "Environments: dev, staging, prod"
  exit 1
fi

VARFILE="${ENV}.tfvars"
if [[ ! -f "$VARFILE" ]]; then
  echo "Error: $VARFILE not found"
  exit 1
fi

# Read values from var-file
SECRET_PREFIX=$(grep "^secret_prefix" "$VARFILE" | awk -F'"' '{print $2}' || awk '{print $3}' "$VARFILE")
PROJECT_ID=$(grep "^project_id" "$VARFILE" | awk -F'"' '{print $2}' || awk '{print $3}' "$VARFILE")
REGION=$(grep "^region" "$VARFILE" | awk -F'"' '{print $2}' || awk '{print $3}' "$VARFILE")
ZONE="${REGION:-us-central1}-b"

echo "=== Terraform Import for environment: $ENV ==="
echo "    secret_prefix: $SECRET_PREFIX"
echo "    project_id:    $PROJECT_ID"
echo "    region:        $REGION"
echo "    zone:          $ZONE"
echo ""

cd "$(dirname "$0")"

# Initialize terraform (don't prompt)
terraform init -backend-config="prefix=dev-nexus/$ENV" -input=false 2>/dev/null

# ============================================================
# IMPORT COMMANDS — add new resources here
# Format: terraform import "resource_type.resource_name" "gcp-resource-id"
# ============================================================

# Compute — names are environment-agnostic (no prefix in name)
import_compute() {
  local resource="$1"; local gcp_id="$2"
  echo "  Importing compute: $resource"
  terraform import "$resource" "$gcp_id" 2>/dev/null && echo "    OK" || echo "    SKIP/FAIL"
}

# Secrets — GCP project number (not id) is used in secret resource paths
import_secret() {
  local resource="$1"; local secret_name="$2"
  echo "  Importing secret: $resource -> $secret_name"
  terraform import "$resource" "projects/$PROJECT_ID/secrets/$secret_name" 2>/dev/null && echo "    OK" || echo "    SKIP/FAIL"
}

# WIF — always same project/ids regardless of environment
import_wif() {
  local resource="$1"; local gcp_id="$2"
  echo "  Importing WIF: $resource"
  terraform import "$resource" "$gcp_id" 2>/dev/null && echo "    OK" || echo "    SKIP/FAIL"
}

# Storage bucket — prod uses legacy name, dev/staging use secret_prefix naming
import_bucket() {
  local resource="$1"; local bucket_name="$2"
  if [[ "$ENV" == "prod" ]]; then
    bucket_name="globalbiting-dev-postgres-backups"
  fi
  echo "  Importing bucket: $resource -> $bucket_name"
  terraform import "$resource" "$bucket_name" 2>/dev/null && echo "    OK" || echo "    SKIP/FAIL"
}

# Run imports
echo "--- WIF Resources ---"
# NOTE: github-provider (old) is soft-deleted in GCP. Import the new provider instead.
# Also: only SA uses count=0 (implicit) in terraform config; pool and provider don't.
import_wif "google_service_account.github_actions_deploy" \
  "projects/${PROJECT_ID}/serviceAccounts/github-actions-deploy@${PROJECT_ID}.iam.gserviceaccount.com"
import_wif "google_iam_workload_identity_pool.github" \
  "projects/${PROJECT_ID}/locations/global/workloadIdentityPools/github-pool"
import_wif "google_iam_workload_identity_pool_provider.github" \
  "projects/${PROJECT_ID}/locations/global/workloadIdentityPools/github-pool/providers/github-provider-daroja"

echo "--- Secret Manager Secrets (indexed — use [0]) ---"
# These secrets use count = 1 in terraform config, so their addresses have [0]
import_secret "google_secret_manager_secret.langsmith_api_key[0]" \
  "${SECRET_PREFIX}_LANGSMITH_API_KEY"
import_secret "google_secret_manager_secret.pattern_miner_token[0]" \
  "${SECRET_PREFIX}_PATTERN_MINER_TOKEN"
import_secret "google_secret_manager_secret.action_agent_token[0]" \
  "${SECRET_PREFIX}_ACTION_AGENT_TOKEN"
import_secret "google_secret_manager_secret.orchestrator_token[0]" \
  "${SECRET_PREFIX}_ORCHESTRATOR_TOKEN"

echo "--- Secret Manager Secrets (non-indexed) ---"
# These secrets have no count in terraform config — no [0]
import_secret "google_secret_manager_secret.github_client_id" \
  "${SECRET_PREFIX}_GITHUB_CLIENT_ID"
import_secret "google_secret_manager_secret.github_client_secret" \
  "${SECRET_PREFIX}_GITHUB_CLIENT_SECRET"
import_secret "google_secret_manager_secret.jwt_secret" \
  "${SECRET_PREFIX}_JWT_SECRET"
import_secret "google_secret_manager_secret.anthropic_api_key" \
  "${SECRET_PREFIX}_ANTHROPIC_API_KEY"
import_secret "google_secret_manager_secret.postgres_password" \
  "${SECRET_PREFIX}_POSTGRES_PASSWORD"
import_secret "google_secret_manager_secret.postgres_user" \
  "${SECRET_PREFIX}_POSTGRES_USER"
import_secret "google_secret_manager_secret.postgres_db" \
  "${SECRET_PREFIX}_POSTGRES_DB"
import_secret "google_secret_manager_secret.postgres_host" \
  "${SECRET_PREFIX}_POSTGRES_HOST"

echo "--- Compute Resources ---"
import_compute "google_compute_firewall.allow_egress_all[0]" \
  "projects/${PROJECT_ID}/global/firewalls/dev-nexus-allow-egress-all"
import_compute "google_compute_route.default_internet_route[0]" \
  "projects/${PROJECT_ID}/global/routes/dev-nexus-default-internet-route"
import_compute "google_compute_disk.postgres_data[0]" \
  "projects/${PROJECT_ID}/zones/${ZONE}/disks/dev-nexus-postgres-data"
import_compute "google_compute_address.postgres_external_ip[0]" \
  "projects/${PROJECT_ID}/regions/${REGION}/addresses/dev-nexus-postgres-external-ip"

echo "--- Storage Buckets ---"
# NOTE: If bucket was created with a different prefix, adjust the bucket name here
import_bucket "google_storage_bucket.postgres_backups[0]" \
  "${SECRET_PREFIX}-postgres-backups"

# ============================================================
echo ""
echo "=== Import complete ==="
echo "Run 'terraform plan -var-file=$VARFILE' to verify state."
