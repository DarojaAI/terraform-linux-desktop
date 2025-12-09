# Terraform Variables for dev-nexus

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
  description = "Labels to apply to all resources"
  type        = map(string)
  default = {
    application = "dev-nexus"
    managed_by  = "terraform"
    environment = "production"
  }
}
