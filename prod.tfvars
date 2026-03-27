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

# ====================================
# Frontend Configuration
# ====================================

frontend_url = "https://dev-nexus-frontend-noig7bsv5-milan-patels-projects-187b35de.vercel.app"

# ====================================
# GCP Configuration
# ====================================

project_id = "globalbiting-dev"  # Change to production GCP project if separate
region     = "us-central1"

# ====================================
# Secrets (ALWAYS use Secret Manager in production!)
# ====================================

# NEVER commit real secrets! Get from Secret Manager:
# gcloud secrets versions access latest --secret="dev-nexus-prod_GITHUB_TOKEN"
# gcloud secrets versions access latest --secret="dev-nexus-prod_ANTHROPIC_API_KEY"
# gcloud secrets versions access latest --secret="dev-nexus-prod_POSTGRES_PASSWORD"
github_token      = "prod_github_token_from_secret_manager"
anthropic_api_key = "prod_anthropic_key_from_secret_manager"
postgres_db_password = "prod_db_password_from_secret_manager"

# ====================================
# LangSmith Configuration (LLM Observability)
# ====================================

langsmith_api_key           = ""  # Get from https://smith.langchain.com/
langsmith_project           = "dev-nexus-prod"
langsmith_tracing_enabled   = false
langsmith_endpoint          = "https://api.smith.langchain.com"

# ====================================
# Knowledge Base
# ====================================

knowledge_base_repo = "patelmm79/dev-nexus"

# ====================================
# Cloud Run - Production Settings
# ====================================

# High availability with consistent performance
cpu                  = "2"
memory               = "2Gi"
cpu_always_allocated = true   # NO cold starts in production
min_instances        = 1      # Always have at least 1 instance running
max_instances        = 20     # Allow significant scale
timeout_seconds      = 300

# ====================================
# Security - Production Settings
# ====================================

# REQUIRED: Authenticate all requests in production
allow_unauthenticated = false

# Create and use service accounts for all integrations
allowed_service_accounts = []
create_external_service_accounts = true

# Restrict CORS to production domains only
allowed_origin_regex = "https://dev-nexus\\.example\\.com|https://.*-prod\\.vercel\\.app"

# ====================================
# Integration
# ====================================

# External A2A Agent URLs and Tokens
# Pattern-miner and orchestrator do not currently require authentication
# Tokens are optional (infrastructure supports them for future use)
# Leave tokens empty for now
#
# If implementing tokens in the future, get from GCP Secret Manager:
#   gcloud secrets versions access latest --secret="dev-nexus-prod_ORCHESTRATOR_TOKEN"
#   gcloud secrets versions access latest --secret="dev-nexus-prod_PATTERN_MINER_TOKEN"

orchestrator_url    = "https://orchestrator-prod.run.app"     # Production orchestrator URL
orchestrator_token  = ""                                       # Optional, not required
log_attacker_url    = "https://log-attacker-prod.run.app"     # Production log-attacker URL
pattern_miner_url   = "https://pattern-miner-prod.run.app"    # Production pattern-miner URL
pattern_miner_token = ""                                       # Optional, not required

# ====================================
# Monitoring
# ====================================

enable_monitoring_alerts      = true
alert_notification_channels   = []  # Add production notification channels (PagerDuty, Slack, etc.)
error_rate_threshold          = 1.0  # Lower threshold for production
latency_threshold_ms          = 1000 # Stricter latency requirements

# ====================================
# Resource Labels
# ====================================

labels = {
  application = "dev-nexus"
  managed_by  = "terraform"
  team        = "platform"
  environment-tier = "production"
}

# ====================================
# PostgreSQL - Production Settings
# ====================================

postgres_version          = "15"
postgres_machine_type     = "e2-small"  # More resources for production
postgres_disk_size_gb     = 100         # More capacity for production data
postgres_subnet_cidr      = "10.8.0.0/24"
vpc_connector_cidr        = "10.8.1.0/28"
allow_ssh_from_cidrs      = ["YOUR_OFFICE_IP/32"]  # RESTRICT: Set to your office IP
backup_retention_days     = 30          # Keep 30 days of backups
enable_postgres_monitoring = true       # Enable all monitoring in prod
