# Production Environment Terraform Configuration
# Initialize with:
#   terraform init -backend-config="prefix=dev-nexus/prod"
# Plan/Apply:
#   terraform plan -var-file="prod.tfvars"
#   terraform apply -var-file="prod.tfvars"

# ====================================
# Environment Settings (REQUIRED)
# ====================================

environment   = "prod"
secret_prefix = "dev-nexus-prod"
repo_nickname = "dev-nexus"

# Frontend URL for OAuth callback
# Set via GitHub Actions env variable PROD_FRONTEND_URL (enforced by InfrastructureContract)
# DO NOT hardcode here — terraform receives it via TF_VAR_frontend_url from the contract validator
# frontend_url = "https://dev-nexus-frontend.patelmm79.workers.dev"

# Backend Cloud Run URL for OAuth callback
# Set via GitHub Actions env variable PROD_BACKEND_URL (enforced by InfrastructureContract)
# DO NOT hardcode here — terraform receives it via TF_VAR_backend_url from the contract validator
# backend_url = "https://pattern-discovery-agent-uc.a.run.app"

# ====================================
# GCP Configuration
# ====================================

project_id = "globalbiting-dev"
region     = "us-central1"

# ====================================
# GitHub Actions WIF
# ====================================

github_actions_enabled = true
github_actions_scope   = "organization" # "repository" (single repo) or "organization" (all org repos)
github_repo            = "DarojaAI/dev-nexus"
github_org             = "DarojaAI" # required when github_actions_scope = "organization"

# ====================================
# Secrets (Use Secret Manager in production!)
# ====================================

# IMPORTANT: These secrets are injected via TF_VAR_* environment variables in CI.
# Do NOT set them here — tfvars override env vars and would blank out the values.
# github_token, github_client_id, github_client_secret, anthropic_api_key, jwt_secret
# are all provided by the GitHub Actions prod environment secrets.
# RESET: Generated new password on 2026-04-26 03:22 UTC
postgres_db_password = "wBIYv1NWL4udEoSZSB7P"

# ====================================
# LangSmith Configuration (LLM Observability)
# ====================================

langsmith_api_key         = "" # Get from https://smith.langchain.com/
langsmith_project         = "dev-nexus-prod"
langsmith_tracing_enabled = true
langsmith_endpoint        = "https://api.smith.langchain.com"

# ====================================
# Knowledge Base
# ====================================

knowledge_base_repo = "DarojaAI/dev-nexus"
github_owner        = "DarojaAI"

# ====================================
# Cloud Run - Production Settings
# ====================================

cpu                  = "2"
memory               = "2Gi"
cpu_always_allocated = true # Always-on for production latency
min_instances        = 1
max_instances        = 20
timeout_seconds      = 300

# ====================================
# Security - Production Settings
# ====================================

allow_unauthenticated  = true
require_auth_for_write = true

# Service accounts
allowed_service_accounts         = []
create_external_service_accounts = false
allow_ssh_from_cidrs             = []                   # No SSH in prod
allow_postgres_from_cidrs        = ["100.38.44.126/32"] # Local machine for testing

# ====================================
# Integration (Optional)
# ====================================

action_agent_url    = ""
action_agent_token  = ""
orchestrator_url    = ""
orchestrator_token  = ""
log_attacker_url    = ""
pattern_miner_url   = ""
pattern_miner_token = ""

# ====================================
# Monitoring
# ====================================

enable_monitoring_alerts    = true
alert_notification_channels = [] # Configure production alerting
error_rate_threshold        = 1.0
latency_threshold_ms        = 1000
enable_scheduled_backups    = true

# ====================================
# Resource Labels
# ====================================

labels = {
  application = "dev-nexus"
  managed_by  = "terraform"
  team        = "platform"
  environment = "prod"
}

# ====================================
# PostgreSQL - Production Settings
# ====================================

postgres_db_name           = "pattern_discovery"
postgres_db_user           = "app_user"
postgres_version           = "15"
postgres_machine_type      = "e2-medium" # Production tier
postgres_disk_size_gb      = 100
postgres_subnet_cidr       = "10.8.0.0/24"
vpc_connector_cidr         = "10.8.1.0/28"
backup_retention_days      = 30
enable_postgres_monitoring = true

# ====================================
# dbt - Production Settings
# ====================================

dbt_enabled                  = true
dbt_schedule                 = "0 2 * * *" # 2 AM UTC daily
dbt_timeout_seconds          = 3600        # 1 hour max
failure_notification_channel = ""          # Set Slack webhook if needed

# ====================================
# Monitoring Alert Email
# ====================================

monitoring_alert_email = "team@example.com" # Update with real email
