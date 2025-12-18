# Staging Environment Terraform Configuration
# Initialize with:
#   terraform init -backend-config="prefix=dev-nexus/staging"
# Plan/Apply:
#   terraform plan -var-file="staging.tfvars"
#   terraform apply -var-file="staging.tfvars"

# ====================================
# Environment Settings (REQUIRED)
# ====================================

environment   = "staging"
secret_prefix = "dev-nexus-staging"

# ====================================
# GCP Configuration
# ====================================

project_id = "globalbiting-dev"
region     = "us-central1"

# ====================================
# Secrets (Use Secret Manager!)
# ====================================

# Get staging secrets from Secret Manager:
# gcloud secrets versions access latest --secret="dev-nexus-staging_GITHUB_TOKEN"
# gcloud secrets versions access latest --secret="dev-nexus-staging_ANTHROPIC_API_KEY"
# gcloud secrets versions access latest --secret="dev-nexus-staging_POSTGRES_PASSWORD"
github_token      = "staging_github_token_from_secret_manager"
anthropic_api_key = "staging_anthropic_key_from_secret_manager"
postgres_db_password = "staging_db_password_from_secret_manager"

# ====================================
# Knowledge Base
# ====================================

knowledge_base_repo = "patelmm79/dev-nexus"

# ====================================
# Cloud Run - Staging Settings
# ====================================

# Mid-tier resource allocation for testing
cpu                  = "1"
memory               = "2Gi"
cpu_always_allocated = false  # Allow cold starts
min_instances        = 0      # Scale to zero to save costs
max_instances        = 10     # Allow more instances for load testing
timeout_seconds      = 300

# ====================================
# Security - Staging Settings
# ====================================

# Require authentication for staging
allow_unauthenticated = false

# Create service accounts for external integrations
allowed_service_accounts = []
create_external_service_accounts = true  # For testing with orchestrator/log-attacker

# CORS for staging frontend deployments
allowed_origin_regex = "https://.*-milan-patels-projects-187b35de\\.vercel\\.app|https://staging-.*\\.vercel\\.app"

# ====================================
# Integration
# ====================================

orchestrator_url = ""  # Add staging orchestrator URL when available
log_attacker_url = ""  # Add staging log-attacker URL when available

# ====================================
# Monitoring
# ====================================

enable_monitoring_alerts      = true
alert_notification_channels   = []  # Add staging notification channels
error_rate_threshold          = 5.0
latency_threshold_ms          = 5000

# ====================================
# Resource Labels
# ====================================

labels = {
  application = "dev-nexus"
  managed_by  = "terraform"
  team        = "platform"
}

# ====================================
# PostgreSQL - Staging Settings
# ====================================

postgres_db_password      = "staging_db_password_from_secret_manager"
postgres_db_name          = "devnexus"
postgres_db_user          = "devnexus"
postgres_version          = "15"
postgres_machine_type     = "e2-micro"  # Cost-effective
postgres_disk_size_gb     = 50          # More space for testing
postgres_subnet_cidr      = "10.8.0.0/24"
vpc_connector_cidr        = "10.8.1.0/28"
allow_ssh_from_cidrs      = ["0.0.0.0/0"]  # Restrict in production!
backup_retention_days     = 14
enable_postgres_monitoring = true
