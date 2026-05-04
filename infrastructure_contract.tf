# terraform/infrastructure_contract.tf
# Infrastructure Data Contract
#
# Single source of truth for per-environment sizing, HA, and networking rules.
# Consumed by main.tf via local.env_contract.
#
# Reusable pattern sourced from rag-research-tool/deploy/terraform/internal/infrastructure-contract.tf
# and adapted for dev-nexus (Cloud Run instead of Cloud SQL, dev/prod environments).

# =============================================================================
# Contract Matrix
# =============================================================================

locals {
  infrastructure_contract = {
    dev = {
      # Minimal cost — scale-to-zero, single-AZ, no HA
      cloud_run_cpu         = "1"
      cloud_run_memory      = "1Gi"
      cloud_run_min_scale   = 0       # Scale to zero
      cloud_run_max_scale   = 5
      cpu_always_allocated  = false
      postgres_machine_type = "e2-micro"
      postgres_disk_size_gb = 30
      backup_retention_days = 7
      ha_enabled            = false
      allowed_cidrs         = ["0.0.0.0/0"] # Open in dev
    }

    staging = {
      # Balanced cost/resilience
      cloud_run_cpu         = "2"
      cloud_run_memory      = "2Gi"
      cloud_run_min_scale   = 1
      cloud_run_max_scale   = 10
      cpu_always_allocated  = true
      postgres_machine_type = "e2-small"
      postgres_disk_size_gb = 50
      backup_retention_days = 14
      ha_enabled            = false
      allowed_cidrs         = ["10.0.0.0/8"]
    }

    prod = {
      # High reliability — always-on, HA, restricted networking
      cloud_run_cpu         = "2"
      cloud_run_memory      = "2Gi"
      cloud_run_min_scale   = 1
      cloud_run_max_scale   = 20
      cpu_always_allocated  = true
      postgres_machine_type = "e2-medium"
      postgres_disk_size_gb = 100
      backup_retention_days = 30
      ha_enabled            = true
      allowed_cidrs         = ["10.0.0.0/8"]
    }
  }

  # Active environment contract — reference this in resource definitions
  env_contract = local.infrastructure_contract[var.environment]
}

# =============================================================================
# Contract Validation (Terraform check blocks — run at plan time, no state)
# =============================================================================

# Rule: prod disk must be >= 2x dev disk (sizing progression)
check "prod_disk_gte_2x_dev" {
  assert {
    condition = (
      local.infrastructure_contract.prod.postgres_disk_size_gb >=
      local.infrastructure_contract.dev.postgres_disk_size_gb * 2
    )
    error_message = "CONTRACT VIOLATION: prod postgres_disk_size_gb must be >= 2x dev. prod=${local.infrastructure_contract.prod.postgres_disk_size_gb}, dev=${local.infrastructure_contract.dev.postgres_disk_size_gb}"
  }
}

# Rule: prod must always keep min 1 instance (no cold starts in production)
check "prod_min_scale_nonzero" {
  assert {
    condition     = local.infrastructure_contract.prod.cloud_run_min_scale >= 1
    error_message = "CONTRACT VIOLATION: prod cloud_run_min_scale must be >= 1 to prevent cold starts. Got: ${local.infrastructure_contract.prod.cloud_run_min_scale}"
  }
}

# Rule: prod must have cpu_always_allocated = true
check "prod_cpu_always_allocated" {
  assert {
    condition     = local.infrastructure_contract.prod.cpu_always_allocated == true
    error_message = "CONTRACT VIOLATION: prod cpu_always_allocated must be true to prevent request timeout during cold CPU reclaim."
  }
}

# Rule: prod backup retention must be >= 30 days
check "prod_backup_retention" {
  assert {
    condition     = local.infrastructure_contract.prod.backup_retention_days >= 30
    error_message = "CONTRACT VIOLATION: prod backup_retention_days must be >= 30 for compliance. Got: ${local.infrastructure_contract.prod.backup_retention_days}"
  }
}

# Rule: dev must scale to zero (cost control)
check "dev_scales_to_zero" {
  assert {
    condition     = local.infrastructure_contract.dev.cloud_run_min_scale == 0
    error_message = "CONTRACT VIOLATION: dev cloud_run_min_scale must be 0 (scale-to-zero for cost control). Got: ${local.infrastructure_contract.dev.cloud_run_min_scale}"
  }
}

# =============================================================================
# Contract Outputs — visible in terraform apply output for traceability
# =============================================================================

output "infrastructure_contract_environment" {
  value       = var.environment
  description = "Active environment for this deployment"
}

output "infrastructure_contract_config" {
  value       = local.env_contract
  description = "Infrastructure contract spec applied to this deployment"
}

output "infrastructure_contract_applied" {
  value       = true
  description = "Infrastructure contract validated and applied"
}
