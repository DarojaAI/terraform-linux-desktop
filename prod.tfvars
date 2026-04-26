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

# Frontend URL for OAuth callback
frontend_url = "https://dev-nexus-frontend.patelmm79.workers.dev"

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

# IMPORTANT: Get actual values from Secret Manager:
# gcloud secrets versions access latest --secret="dev-nexus-prod_GITHUB_TOKEN"
github_token         = ""                                     # Set from Secret Manager
github_client_id     = ""                                     # Set from Secret Manager
github_client_secret = ""                                     # Set from Secret Manager
anthropic_api_key    = ""                                     # Set from Secret Manager
jwt_secret           = "prod-jwt-secret-placeholder-32chars!" # Set from Secret Manager (min 32 chars)
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
allow_ssh_from_cidrs             = [] # No SSH in prod
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
