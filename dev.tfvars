# Development Environment Terraform Configuration
# Copy from this file when using dev environment:
#   terraform init -backend-config="prefix=dev-nexus/dev"
#   terraform plan -var-file="dev.tfvars"
#   terraform apply -var-file="dev.tfvars"

# ====================================
# Environment Settings (REQUIRED)
# ====================================

environment   = "dev"
secret_prefix = "dev-nexus-dev"

# ====================================
# GCP Configuration
# ====================================

project_id = "globalbiting-dev"
region     = "us-central1"

# ====================================
# Secrets (Use Secret Manager in production!)
# ====================================

# IMPORTANT: For development only - use actual values from Secret Manager in production
# Get values from: gcloud secrets versions access latest --secret="dev-nexus-dev_GITHUB_TOKEN" etc.
github_token      = "github_pat_dev_placeholder"      # Replace with actual token from Secret Manager
anthropic_api_key = "sk-ant-dev-placeholder"          # Replace with actual key from Secret Manager
postgres_db_password = "dev-db-password-placeholder"  # Replace with actual password from Secret Manager

# ====================================
# Knowledge Base
# ====================================

knowledge_base_repo = "patelmm79/dev-nexus"

# ====================================
# Cloud Run - Development Settings
# ====================================

# Keep resource usage low for cost-efficiency
cpu                  = "1"
memory               = "1Gi"
cpu_always_allocated = false  # Allow cold starts in dev
min_instances        = 0      # Scale to zero for cost savings
max_instances        = 5      # Lower max for dev testing
timeout_seconds      = 300

# ====================================
# Security - Development Settings
# ====================================

# Unauthenticated access for easier local testing
allow_unauthenticated = true

# For local testing/staging
allowed_service_accounts = []
create_external_service_accounts = false

# CORS for local development
allowed_origin_regex = "https://.*-milan-patels-projects-187b35de\\.vercel\\.app|http://localhost:3000|http://localhost:5173"

# ====================================
# Integration (Optional)
# ====================================

orchestrator_url = ""  # Add if orchestrator-dev service exists
log_attacker_url = ""  # Add if log-attacker-dev service exists

# ====================================
# Monitoring
# ====================================

enable_monitoring_alerts      = false
alert_notification_channels   = []
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
# PostgreSQL - Development Settings
# ====================================

postgres_db_name          = "devnexus"
postgres_db_user          = "devnexus"
postgres_version          = "15"
postgres_machine_type     = "e2-micro"  # FREE tier eligible
postgres_disk_size_gb     = 30          # FREE tier eligible (30GB free)
postgres_subnet_cidr      = "10.8.0.0/24"
vpc_connector_cidr        = "10.8.1.0/28"
allow_ssh_from_cidrs      = ["0.0.0.0/0"]  # Restrict in production!
backup_retention_days     = 7
enable_postgres_monitoring = false
