# =============================================================================
# GitHub Actions Workload Identity Federation
# =============================================================================
# Sets up GCP Workload Identity Federation so GitHub Actions can deploy
# to Cloud Run without storing service account keys.
#
# Usage:
#   In your environment's .tfvars file, set:
#     github_actions_enabled = true
#     github_repo = "patelmm79/dev-nexus"
#     github_owner = "patelmm79"
#
#   Then run:
#     terraform plan -var-file=prod.tfvars -out=tfplan
#     terraform apply tfplan
#
# After apply, Terraform outputs the values needed for GitHub secrets:
#   - WIF_PROVIDER: the workload identity provider resource name
#   - WIF_SERVICE_ACCOUNT: the deploy service account email
# =============================================================================

resource "google_project_service" "iam" {
  service            = "iam.googleapis.com"
  disable_on_destroy = false
}

resource "google_project_service" "sts" {
  service            = "sts.googleapis.com"
  disable_on_destroy = false
}

# =============================================================================
# Service Account for GitHub Actions Deployment
# =============================================================================

resource "google_service_account" "github_actions_deploy" {
  project      = var.project_id
  account_id   = "github-actions-deploy"
  display_name = "GitHub Actions Deployment"
  description  = "Service account used by GitHub Actions to deploy dev-nexus"
}

# =============================================================================
# Workload Identity Pool
# =============================================================================

resource "google_iam_workload_identity_pool" "github" {
  project                   = var.project_id
  workload_identity_pool_id  = "github-pool"
  display_name               = "GitHub Actions"
  description                = "Workload Identity Pool for GitHub Actions"
  disabled                   = !var.github_actions_enabled
}

# =============================================================================
# Workload Identity Pool Provider
# =============================================================================

resource "google_iam_workload_identity_pool_provider" "github" {
  project                            = var.project_id
  workload_identity_pool_id          = google_iam_workload_identity_pool.github.workload_identity_pool_id
  workload_identity_pool_provider_id = "github-provider"
  display_name                      = "patelmm79/dev-nexus"
  description                       = "GitHub Actions provider for patelmm79/dev-nexus"

  attribute_mapping = {
    "google.subject"           = "assertion.sub"
    "attribute.aud"           = "assertion.aud"
    "attribute.repository"    = "assertion.repository"
  }

  # NOTE: attribute_condition is intentionally unset (="").
  # GCP auto-generates a condition when only google.subject is mapped,
  # and that auto-generated condition may reference unmapped claims like
  # attribute.repository, causing validation failures.
  # Repo-level access control is handled by the IAM binding on the SA:
  # principalSet://iam.googleapis.com/{pool}/attribute.repository/${var.github_repo}
  attribute_condition = ""

  oidc {
    issuer_uri = "https://token.actions.githubusercontent.com"
  }
}

# =============================================================================
# Allow the Workload Identity Pool to Impersonate the Deploy SA
# =============================================================================

resource "google_service_account_iam_member" "wif_impersonate" {
  service_account_id = google_service_account.github_actions_deploy.name
  role           = "roles/iam.workloadIdentityUser"
  member         = "principalSet://iam.googleapis.com/${google_iam_workload_identity_pool.github.name}/attribute.repository/${var.github_repo}"
}

# Allow WIF pool to mint access tokens for the deploy SA (needed for token_format: access_token)
resource "google_service_account_iam_member" "wif_token_creator" {
  service_account_id = google_service_account.github_actions_deploy.name
  role               = "roles/iam.serviceAccountTokenCreator"
  member             = "principalSet://iam.googleapis.com/${google_iam_workload_identity_pool.github.name}/attribute.repository/${var.github_repo}"
}

# Pool-level binding (no attribute restriction) — for testing only
# If this works but the attribute-based one doesn't, the issue is with
# how google-github-actions/auth sends the repository attribute in the OIDC token
resource "google_service_account_iam_member" "wif_token_creator_pool" {
  service_account_id = google_service_account.github_actions_deploy.name
  role               = "roles/iam.serviceAccountTokenCreator"
  member             = "principalSet://iam.googleapis.com/${google_iam_workload_identity_pool.github.name}"
}

# =============================================================================
# Grant Deploy SA Project Editor (dev/staging only — use narrower roles in prod)
# =============================================================================

resource "google_project_iam_member" "deploy_editor" {
  project = var.project_id
  role    = "roles/editor"
  member   = "serviceAccount:${google_service_account.github_actions_deploy.email}"
}

# =============================================================================
# Outputs — Use These for GitHub Secrets
# =============================================================================

output "wif_provider" {
  description = "Workload Identity Provider resource name — use as WIF_PROVIDER secret in GitHub"
  value      = google_iam_workload_identity_pool.github.name
  # Output format: projects/PROJECT_NUMBER/locations/global/workloadIdentityPools/github-pool
}

output "wif_provider_full" {
  description = "Full WIF Provider resource name (including the provider itself) — for reference"
  value      = google_iam_workload_identity_pool_provider.github.name
  # Output format: projects/PROJECT_NUMBER/locations/global/workloadIdentityPools/github-pool/providers/github-provider
}

output "wif_service_account" {
  description = "Deploy service account email — use as WIF_SERVICE_ACCOUNT secret in GitHub"
  value      = google_service_account.github_actions_deploy.email
}

output "github_actions_setup_complete" {
  description = "Whether GitHub Actions WIF is fully configured"
  value      = var.github_actions_enabled ? true : false
}

# =============================================================================
# Usage Instructions (as output for terraform apply output)
# =============================================================================

output "github_secrets_instructions" {
  description = "Instructions for setting up GitHub Actions secrets"
  value       = <<-EOT

  ============================================
  GitHub Actions WIF Setup Complete!
  ============================================

  Add these TWO secrets to your GitHub repository:
  https://github.com/patelmm79/dev-nexus/settings/secrets/actions

  1. WIF_PROVIDER =
     ${google_iam_workload_identity_pool.github.name}/providers/github-provider

  2. WIF_SERVICE_ACCOUNT =
     ${google_service_account.github_actions_deploy.email}

  ============================================
  EOT
}
