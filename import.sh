#!/bin/bash
# Import existing GCP resources into terraform state

TF_VAR_environment=prod

terraform init -backend-config="prefix=dev-nexus/$TF_VAR_environment" 2>&1 | tail -3

# WIF resources
terraform import "google_service_account.github_actions_deploy[0]" "projects/globalbiting-dev/serviceAccounts/github-actions-deploy@globalbiting-dev.iam.gserviceaccount.com" 2>&1
terraform import "google_iam_workload_identity_pool.github[0]" "projects/globalbiting-dev/locations/global/workloadIdentityPools/github-pool" 2>&1

# Secrets
terraform import "google_secret_manager_secret.github_client_id[0]" "projects/665374072631/secrets/dev-nexus-prod_GITHUB_CLIENT_ID" 2>&1
terraform import "google_secret_manager_secret.github_client_secret[0]" "projects/665374072631/secrets/dev-nexus-prod_GITHUB_CLIENT_SECRET" 2>&1
terraform import "google_secret_manager_secret.jwt_secret[0]" "projects/665374072631/secrets/dev-nexus-prod_JWT_SECRET" 2>&1
terraform import "google_secret_manager_secret.langsmith_api_key[0]" "projects/665374072631/secrets/dev-nexus-prod_LANGSMITH_API_KEY" 2>&1
terraform import "google_secret_manager_secret.postgres_user[0]" "projects/665374072631/secrets/dev-nexus-prod_POSTGRES_USER" 2>&1
terraform import "google_secret_manager_secret.postgres_db[0]" "projects/665374072631/secrets/dev-nexus-prod_POSTGRES_DB" 2>&1
terraform import "google_secret_manager_secret.postgres_host[0]" "projects/665374072631/secrets/dev-nexus-prod_POSTGRES_HOST" 2>&1

echo "Import complete"
