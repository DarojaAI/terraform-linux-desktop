# Terraform Variables for dev-nexus

# ====================================
# GitHub Actions Workload Identity Federation
# ====================================

variable "github_actions_enabled" {
  description = "Enable GitHub Actions Workload Identity Federation for CI/CD deployment"
  type        = bool
  default     = true
}

variable "github_repo" {
  description = "GitHub repository in 'owner/repo' format (e.g., 'DarojaAI/dev-nexus') — used when github_actions_scope is 'repository'"
  type        = string
  default     = "DarojaAI/dev-nexus"
}

variable "github_owner" {
  description = "GitHub repository owner (e.g., 'DarojaAI')"
  type        = string
  default     = "DarojaAI"
}

variable "github_org" {
  description = "GitHub organization slug (e.g., 'DarojaAI') — used when github_actions_scope is 'organization'. All repos in this org will be able to authenticate."
  type        = string
  default     = ""
}

variable "github_actions_scope" {
  description = "Scope for GitHub Actions WIF access. 'repository' = single repo (strictest). 'organization' = all repos in github_org (less restrictive)."
  type        = string
  default     = "repository"

  validation {
    condition     = contains(["repository", "organization"], var.github_actions_scope)
    error_message = "github_actions_scope must be 'repository' or 'organization'."
  }
}

# ====================================
# Environment Configuration (REQUIRED)
# ====================================

variable "environment" {
  description = "Environment name (dev, staging, prod) - used for resource naming and state isolation"
  type        = string

  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "Environment must be 'dev', 'staging', or 'prod'."
  }
}

variable "secret_prefix" {
  description = "Prefix for secrets in Google Secret Manager (e.g., 'dev-nexus-dev', 'dev-nexus-prod'). Prevents collisions between environments."
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9-]{2,}[a-z0-9]$", var.secret_prefix))
    error_message = "Secret prefix must start and end with lowercase letter or number, contain only lowercase letters, numbers, and hyphens, and be at least 4 characters."
  }
}

# ====================================
# Required Variables
# ====================================

variable "project_id" {
  description = "Google Cloud Project ID"
  type        = string
}

variable "region" {
  description = "Google Cloud region for deployment"
  type        = string
  default     = "us-central1"
}

variable "github_token" {
  description = "GitHub personal access token with repo access"
  type        = string
  sensitive   = true
}

variable "github_client_id" {
  description = "GitHub OAuth App client ID for user authentication"
  type        = string
  sensitive   = true
}

variable "github_client_secret" {
  description = "GitHub OAuth App client secret for user authentication"
  type        = string
  sensitive   = true
}

variable "jwt_secret" {
  description = "Secret key for signing JWT tokens (minimum 32 characters)"
  type        = string
  sensitive   = true

  validation {
    condition     = length(var.jwt_secret) >= 32
    error_message = "JWT_SECRET must be at least 32 characters for security."
  }
}

variable "frontend_url" {
  description = "Frontend URL for OAuth callback redirects"
  type        = string
  default     = ""
}

variable "backend_url" {
  description = "Backend URL for OAuth callback"
  type        = string
}

variable "jwt_expire_hours" {
  description = "Hours until JWT token expires"
  type        = number
  default     = 8

  validation {
    condition     = var.jwt_expire_hours >= 1 && var.jwt_expire_hours <= 72
    error_message = "JWT_EXPIRE_HOURS must be between 1 and 72 hours."
  }
}

variable "anthropic_api_key" {
  description = "Anthropic API key for Claude"
  type        = string
  sensitive   = true
}

# ====================================
# LangSmith Configuration
# ====================================

variable "langsmith_api_key" {
  description = "LangSmith API key for LLM observability and tracing"
  type        = string
  sensitive   = true
  default     = ""
}

variable "langsmith_project" {
  description = "LangSmith project name for organizing traces (e.g., 'dev-nexus-prod')"
  type        = string
  default     = "dev-nexus"
}

variable "langsmith_tracing_enabled" {
  description = "Enable LangSmith tracing (true/false)"
  type        = bool
  default     = false
}

variable "langsmith_endpoint" {
  description = "LangSmith API endpoint (default: https://api.smith.langchain.com)"
  type        = string
  default     = "https://api.smith.langchain.com"
}

variable "knowledge_base_repo" {
  description = "GitHub repository for knowledge base storage (format: owner/repo)"
  type        = string
}

# ====================================
# Cloud Run Configuration
# ====================================

variable "cpu" {
  description = "Number of vCPUs for Cloud Run container"
  type        = string
  default     = "1"

  validation {
    condition     = contains(["1", "2", "4", "8"], var.cpu)
    error_message = "CPU must be 1, 2, 4, or 8."
  }
}

variable "memory" {
  description = "Memory allocation for Cloud Run container"
  type        = string
  default     = "1Gi"

  validation {
    condition     = can(regex("^[0-9]+(Mi|Gi)$", var.memory))
    error_message = "Memory must be in format like 512Mi, 1Gi, 2Gi, etc."
  }
}

variable "cpu_always_allocated" {
  description = "Whether CPU is always allocated (prevents cold starts)"
  type        = bool
  default     = false
}

variable "min_instances" {
  description = "Minimum number of Cloud Run instances (0 = scale to zero)"
  type        = number
  default     = 0

  validation {
    condition     = var.min_instances >= 0 && var.min_instances <= 100
    error_message = "min_instances must be between 0 and 100."
  }
}

variable "max_instances" {
  description = "Maximum number of Cloud Run instances"
  type        = number
  default     = 10

  validation {
    condition     = var.max_instances >= 1 && var.max_instances <= 1000
    error_message = "max_instances must be between 1 and 1000."
  }
}

variable "timeout_seconds" {
  description = "Request timeout in seconds (max 3600)"
  type        = number
  default     = 300

  validation {
    condition     = var.timeout_seconds >= 1 && var.timeout_seconds <= 3600
    error_message = "timeout_seconds must be between 1 and 3600."
  }
}

# ====================================
# Security Configuration
# ====================================

variable "allow_unauthenticated" {
  description = "Allow unauthenticated access to the service (not recommended for production)"
  type        = bool
  default     = false
}

variable "allowed_service_accounts" {
  description = "List of service account emails allowed to authenticate"
  type        = list(string)
  default     = []
}

variable "require_auth_for_write" {
  description = "Require authentication for write operations (add_deployment_info, add_lesson_learned, etc.). Set to false for development, true for production."
  type        = bool
  default     = false
}

variable "create_external_service_accounts" {
  description = "Create service accounts for external agents (log-attacker, orchestrator)"
  type        = bool
  default     = false
}

variable "create_github_trigger" {
  description = "Create GitHub webhook trigger for Cloud Build (requires GitHub App connection in Cloud Build console)"
  type        = bool
  default     = false
}

# ====================================
# Integration Configuration
# ====================================

variable "orchestrator_url" {
  description = "URL of dependency-orchestrator service (optional)"
  type        = string
  default     = ""
}

variable "log_attacker_url" {
  description = "URL of agentic-log-attacker service (optional)"
  type        = string
  default     = ""
}

variable "pattern_miner_url" {
  description = "URL of pattern-miner service (optional)"
  type        = string
  default     = ""
}

variable "pattern_miner_token" {
  description = "Authentication token for pattern-miner service (optional - not currently required, auth not implemented in pattern-miner yet)"
  type        = string
  sensitive   = true
  default     = ""
}

variable "action_agent_url" {
  description = "URL of action-agent service for executing code changes (optional)"
  type        = string
  default     = ""
}

variable "action_agent_token" {
  description = "Authentication token for action-agent service"
  type        = string
  sensitive   = true
  default     = ""
}

variable "orchestrator_token" {
  description = "Authentication token for dependency-orchestrator service (optional - not currently required, auth not implemented yet)"
  type        = string
  sensitive   = true
  default     = ""
}

# ====================================
# Monitoring Configuration
# ====================================

variable "enable_monitoring_alerts" {
  description = "Enable Cloud Monitoring alerts"
  type        = bool
  default     = false
}

variable "alert_notification_channels" {
  description = "List of notification channel IDs for alerts"
  type        = list(string)
  default     = []
}

variable "error_rate_threshold" {
  description = "Error rate threshold for alerting (percentage)"
  type        = number
  default     = 5.0

  validation {
    condition     = var.error_rate_threshold >= 0 && var.error_rate_threshold <= 100
    error_message = "error_rate_threshold must be between 0 and 100."
  }
}

variable "latency_threshold_ms" {
  description = "P95 latency threshold for alerting (milliseconds)"
  type        = number
  default     = 5000

  validation {
    condition     = var.latency_threshold_ms > 0
    error_message = "latency_threshold_ms must be greater than 0."
  }
}

# ====================================
# Labels and Tags
# ====================================

variable "labels" {
  description = "Labels to apply to all resources (environment label is auto-set from var.environment)"
  type        = map(string)
  default = {
    application = "dev-nexus"
    managed_by  = "terraform"
  }
}

# ====================================
# PostgreSQL Configuration
# ====================================

variable "postgres_machine_type" {
  description = "Machine type for PostgreSQL VM (e2-micro for free tier)"
  type        = string
  default     = "e2-micro"

  validation {
    condition     = contains(["e2-micro", "e2-small", "e2-medium", "n1-standard-1"], var.postgres_machine_type)
    error_message = "Machine type must be e2-micro (free), e2-small, e2-medium, or n1-standard-1."
  }
}

variable "postgres_disk_size_gb" {
  description = "Disk size for PostgreSQL in GB (30 GB free tier)"
  type        = number
  default     = 30

  validation {
    condition     = var.postgres_disk_size_gb >= 10 && var.postgres_disk_size_gb <= 500
    error_message = "Disk size must be between 10 and 500 GB."
  }
}

variable "postgres_version" {
  description = "PostgreSQL major version"
  type        = string
  default     = "15"

  validation {
    condition     = contains(["14", "15", "16", "18"], var.postgres_version)
    error_message = "PostgreSQL version must be 14, 15, 16, or 18."
  }
}

variable "postgres_db_name" {
  description = "PostgreSQL database name"
  type        = string
  default     = "devnexus"
}

variable "postgres_db_user" {
  description = "PostgreSQL database user"
  type        = string
  default     = "devnexus"
}

variable "postgres_db_password" {
  description = "PostgreSQL database password"
  type        = string
  sensitive   = true
}

variable "postgres_subnet_cidr" {
  description = "CIDR range for PostgreSQL subnet"
  type        = string
  default     = "10.8.0.0/24"
}

variable "vpc_connector_cidr" {
  description = "CIDR range for VPC connector (must be /28)"
  type        = string
  default     = "10.8.1.0/28"
}

variable "allow_ssh_from_cidrs" {
  description = "List of CIDR ranges allowed to SSH to PostgreSQL VM"
  type        = list(string)
  default     = ["0.0.0.0/0"] # Restrict in production!
}

variable "allow_postgres_from_cidrs" {
  description = "List of CIDR ranges allowed to connect to PostgreSQL from external sources (e.g., your local IP). Format: '1.2.3.4/32' for single IP. Leave empty to allow only internal VPC access."
  type        = list(string)
  default     = []
}

variable "postgres_external_ip" {
  description = "Assign an external (public) IP to PostgreSQL VM for direct access from local machine (needed for pgAdmin). Requires allow_postgres_from_cidrs to include your IP."
  type        = bool
  default     = false
}

variable "enable_scheduled_backups" {
  description = "Enable daily automatic PostgreSQL backups"
  type        = bool
  default     = false
}

variable "backup_retention_days" {
  description = "Number of days to retain PostgreSQL backups"
  type        = number
  default     = 30

  validation {
    condition     = var.backup_retention_days >= 7 && var.backup_retention_days <= 365
    error_message = "Backup retention must be between 7 and 365 days."
  }
}

variable "backup_schedule" {
  description = "Cron schedule for PostgreSQL backups (default: daily at 2am UTC)"
  type        = string
  default     = "0 2 * * *"
}

variable "enable_postgres_monitoring" {
  description = "Enable Cloud Monitoring for PostgreSQL"
  type        = bool
  default     = true
}

# ====================================
# dbt Configuration
# ====================================

variable "dbt_schedule" {
  description = "Cron expression for scheduled dbt runs (UTC). Default: 2 AM daily (0 2 * * *)"
  type        = string
  default     = "0 2 * * *"
}

variable "dbt_enabled" {
  description = "Enable dbt module deployment and scheduling"
  type        = bool
  default     = true
}

variable "dbt_timeout_seconds" {
  description = "Maximum execution time for dbt jobs in seconds"
  type        = number
  default     = 3600 # 1 hour
}

variable "failure_notification_channel" {
  description = "Slack webhook URL or similar for dbt job failure notifications"
  type        = string
  default     = ""
  sensitive   = true
}

