# Terraform Variables for dev-nexus

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

variable "anthropic_api_key" {
  description = "Anthropic API key for Claude"
  type        = string
  sensitive   = true
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

variable "allowed_origin_regex" {
  description = "A regex to match allowed origins for CORS."
  type        = string
  default     = "https://.*-milan-patels-projects-187b35de\\.vercel\\.app"
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
    condition     = contains(["14", "15", "16"], var.postgres_version)
    error_message = "PostgreSQL version must be 14, 15, or 16."
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
  default     = ["0.0.0.0/0"]  # Restrict in production!
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

variable "enable_postgres_monitoring" {
  description = "Enable Cloud Monitoring for PostgreSQL"
  type        = bool
  default     = true
}
