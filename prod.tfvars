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

orchestrator_url = "https://orchestrator-prod.run.app"  # Add production orchestrator URL
log_attacker_url = "https://log-attacker-prod.run.app"  # Add production log-attacker URL

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

postgres_db_password      = "prod_db_password_from_secret_manager"
postgres_db_name          = "devnexus"
postgres_db_user          = "devnexus"
postgres_version          = "15"
postgres_machine_type     = "e2-small"  # More resources for production
postgres_disk_size_gb     = 100         # More capacity for production data
postgres_subnet_cidr      = "10.8.0.0/24"
vpc_connector_cidr        = "10.8.1.0/28"
allow_ssh_from_cidrs      = ["YOUR_OFFICE_IP/32"]  # RESTRICT: Set to your office IP
backup_retention_days     = 30          # Keep 30 days of backups
enable_postgres_monitoring = true       # Enable all monitoring in prod
