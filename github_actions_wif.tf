# =============================================================================
# GitHub Actions Workload Identity Federation
# =============================================================================
# Sets up GCP Workload Identity Federation so GitHub Actions can deploy
# to Cloud Run without storing service account keys.
#
# Usage:
#   In your environment's .tfvars file, set:
#     github_actions_enabled = true
#     github_repo = "DarojaAI/dev-nexus"
#     github_org  = "DarojaAI"       # required when github_actions_scope = "organization"
#     github_actions_scope = "repository"   # or "organization"
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
  workload_identity_pool_id = "github-pool"
  display_name              = "GitHub Actions"
  description               = "Workload Identity Pool for GitHub Actions"
  disabled                  = !var.github_actions_enabled
}

# =============================================================================
# Workload Identity Pool Provider
#
# NOTE: The prior provider "github-provider" is soft-deleted in GCP (expired
# 2026-05-12) and cannot be recreated. This new provider "github-provider-daroja"
# replaces it with org-wide scope for DarojaAI.
# =============================================================================

resource "google_iam_workload_identity_pool_provider" "github" {
  project                            = var.project_id
  workload_identity_pool_id          = google_iam_workload_identity_pool.github.workload_identity_pool_id
  workload_identity_pool_provider_id = "github-provider-daroja"
  display_name                       = "DarojaAI org"
  description                        = "GitHub Actions provider for DarojaAI organization"

  attribute_mapping = {
    "google.subject"             = "assertion.sub"
    "attribute.aud"              = "assertion.aud"
    "attribute.repository"       = "assertion.repository"
    "attribute.repository_owner" = "assertion.repository_owner"
  }

  # NOTE: attribute_condition must be set explicitly. GCP's auto-generated
  # condition references ALL mapped claims, but the GitHub OIDC token only
  # provides google.subject natively. Setting this prevents GCP's auto-generation.
  #
  # Repository scope: restricts to a single repo (recommended for prod).
  # Organization scope: restricts to all repos owned by the org.
  attribute_condition = var.github_actions_scope == "organization" ? "attribute.repository_owner==\"${var.github_org}\"" : "attribute.repository==\"${var.github_repo}\""

  oidc {
    issuer_uri = "https://token.actions.githubusercontent.com"
  }
}

# =============================================================================
# NOTE: WIF → SA IAM bindings (workloadIdentityUser, serviceAccountTokenCreator)
# are managed via gcloud commands in .github/workflows/terraform-apply.yml, NOT
# via google_service_account_iam_member resources. The terraform provider's IAM
# member format is rejected by GCP's IAM API with "unknown type" errors for
# principalSet:// identifiers. The gcloud approach is tested and works.
# =============================================================================

# =============================================================================
# =============================================================================
# Outputs — Use These for GitHub Secrets
# =============================================================================

output "wif_provider" {
  description = "Workload Identity Provider resource name — use as WIF_PROVIDER secret in GitHub"
  value       = google_iam_workload_identity_pool.github.name
  # Output format: projects/PROJECT_NUMBER/locations/global/workloadIdentityPools/github-pool
}

output "wif_provider_full" {
  description = "Full WIF Provider resource name (including the provider itself) — for reference"
  value       = google_iam_workload_identity_pool_provider.github.name
  # Output format: projects/PROJECT_NUMBER/locations/global/workloadIdentityPools/github-pool/providers/github-provider-daroja
}

output "wif_service_account" {
  description = "Deploy service account email — use as WIF_SERVICE_ACCOUNT secret in GitHub"
  value       = google_service_account.github_actions_deploy.email
}

output "github_actions_setup_complete" {
  description = "Whether GitHub Actions WIF is fully configured"
  value       = var.github_actions_enabled ? true : false
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
  https://github.com/DarojaAI/dev-nexus/settings/secrets/actions

  1. WIF_PROVIDER =
     ${google_iam_workload_identity_pool.github.name}/providers/github-provider-daroja

  2. WIF_SERVICE_ACCOUNT =
     ${google_service_account.github_actions_deploy.email}

  ============================================
  EOT
}
