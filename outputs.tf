# Terraform Outputs for dev-nexus

# ====================================
# Cloud Run Service Outputs
# ====================================

output "service_url" {
  description = "URL of the deployed Cloud Run service"
  value       = google_cloud_run_v2_service.pattern_discovery_agent.uri
}

output "service_name" {
  description = "Name of the Cloud Run service"
  value       = google_cloud_run_v2_service.pattern_discovery_agent.name
}

output "service_location" {
  description = "Location of the Cloud Run service"
  value       = google_cloud_run_v2_service.pattern_discovery_agent.location
}

output "agentcard_url" {
  description = "URL of the A2A AgentCard endpoint"
  value       = "${google_cloud_run_v2_service.pattern_discovery_agent.uri}/.well-known/agent.json"
}

output "health_check_url" {
  description = "URL of the health check endpoint"
  value       = "${google_cloud_run_v2_service.pattern_discovery_agent.uri}/health"
}

# ====================================
# Secret Outputs
# ====================================

output "github_token_secret_id" {
  description = "ID of the GitHub token secret in Secret Manager"
  value       = google_secret_manager_secret.github_token.id
}

output "anthropic_api_key_secret_id" {
  description = "ID of the Anthropic API key secret in Secret Manager"
  value       = google_secret_manager_secret.anthropic_api_key.id
}

# ====================================
# Service Account Outputs
# ====================================

output "log_attacker_service_account_email" {
  description = "Email of the log-attacker service account (if created)"
  value       = var.create_external_service_accounts ? google_service_account.log_attacker[0].email : null
}

output "orchestrator_service_account_email" {
  description = "Email of the orchestrator service account (if created)"
  value       = var.create_external_service_accounts ? google_service_account.orchestrator[0].email : null
}

output "cloud_run_service_account_email" {
  description = "Email of the Cloud Run service account"
  value       = data.google_compute_default_service_account.default.email
}

# ====================================
# Configuration Outputs
# ====================================

output "allowed_service_accounts" {
  description = "List of service accounts allowed to authenticate"
  value       = var.allowed_service_accounts
}

output "is_public" {
  description = "Whether the service allows unauthenticated access"
  value       = var.allow_unauthenticated
}

# ====================================
# Testing Commands
# ====================================

output "test_commands" {
  description = "Commands to test the deployed service"
  value = {
    health_check          = "curl ${google_cloud_run_v2_service.pattern_discovery_agent.uri}/health"
    agentcard             = "curl ${google_cloud_run_v2_service.pattern_discovery_agent.uri}/.well-known/agent.json | jq"
    authenticated_request = var.allow_unauthenticated ? "Not needed (service is public)" : "curl -H \"Authorization: Bearer $(gcloud auth print-identity-token)\" ${google_cloud_run_v2_service.pattern_discovery_agent.uri}/health"
  }
}

# ====================================
# External Agent Configuration
# ====================================

output "external_agent_config" {
  description = "Configuration for external agents to use this service"
  value = var.create_external_service_accounts ? {
    log_attacker = {
      service_account = google_service_account.log_attacker[0].email
      dev_nexus_url   = google_cloud_run_v2_service.pattern_discovery_agent.uri
      env_vars = {
        DEV_NEXUS_URL                = google_cloud_run_v2_service.pattern_discovery_agent.uri
        DEVNEXUS_INTEGRATION_ENABLED = "true"
      }
    }
    orchestrator = {
      service_account = google_service_account.orchestrator[0].email
      dev_nexus_url   = google_cloud_run_v2_service.pattern_discovery_agent.uri
      env_vars = {
        DEV_NEXUS_URL = google_cloud_run_v2_service.pattern_discovery_agent.uri
      }
    }
  } : null
}

# ====================================
# PostgreSQL Outputs (from gcp-postgres-terraform module)
# ====================================

output "postgres_internal_ip" {
  description = "Internal IP address of PostgreSQL VM"
  value       = module.postgres.internal_ip
}

output "postgres_instance_name" {
  description = "Name of the PostgreSQL VM instance"
  value       = module.postgres.instance_name
}

output "postgres_zone" {
  description = "Zone where PostgreSQL VM is deployed"
  value       = module.postgres.zone
}

output "postgres_external_ip" {
  description = "External (ephemeral) IP address of PostgreSQL VM for external access"
  value       = module.postgres.external_ip
}

output "postgres_connection_string_internal" {
  description = "PostgreSQL connection string for Cloud Run (internal VPC)"
  value       = module.postgres.connection_string_internal
  sensitive   = false
}

output "postgres_connection_string_external" {
  description = "PostgreSQL connection string for external access"
  value       = module.postgres.connection_string_external
  sensitive   = false
}

output "postgres_backup_bucket" {
  description = "Cloud Storage bucket for PostgreSQL backups"
  value       = module.postgres.backup_bucket_name
}

output "vpc_connector_name" {
  description = "Name of the VPC connector for Cloud Run to PostgreSQL"
  value       = module.vpc.vpc_connector_name
}

output "vpc_module_outputs" {
  description = "DEBUG: VPC module outputs"
  value = {
    vpc_name = try(module.vpc.vpc_name, "ERROR")
    vpc_connector_name = try(module.vpc.vpc_connector_name, "ERROR")
  }
}

output "postgres_ssh_command" {
  description = "Command to SSH into PostgreSQL VM"
  value       = "gcloud compute ssh ${module.postgres.instance_name} --zone=${module.postgres.zone} --project=${var.project_id}"
}

# ====================================
# Summary
# ====================================

output "cloud_build_trigger_id" {
  description = "ID of the Cloud Build trigger for GitHub integration"
  value       = var.create_github_trigger ? google_cloudbuild_trigger.dev_nexus_github[0].trigger_id : null
}

output "cloud_build_trigger_webhook" {
  description = "URL to view Cloud Build trigger history"
  value       = "https://console.cloud.google.com/cloud-build/triggers?project=${var.project_id}"
}

output "deployment_summary" {
  description = "Summary of the deployment"
  value = {
    service_url       = google_cloud_run_v2_service.pattern_discovery_agent.uri
    region            = var.region
    authentication    = var.allow_unauthenticated ? "Public (unauthenticated)" : "Private (authenticated)"
    min_instances     = var.min_instances
    max_instances     = var.max_instances
    cpu               = var.cpu
    memory            = var.memory
    knowledge_base    = var.knowledge_base_repo
    database          = "PostgreSQL ${var.postgres_version} with pgvector"
    database_location = "${module.postgres.zone} (${module.postgres.internal_ip})"
    backup_bucket     = module.postgres.backup_bucket_name
    cloud_build_url   = "https://console.cloud.google.com/cloud-build/triggers?project=${var.project_id}"
  }
}
# ====================================
# dbt Outputs
# ====================================

output "dbt_service_url" {
  description = "URL of dbt Cloud Run service"
  value       = try(module.dbt.service_url, "dbt module disabled or not deployed")
}

output "dbt_scheduler_job_id" {
  description = "Cloud Scheduler job ID for dbt runs"
  value       = try(module.dbt.scheduler_job_id, null)
}

output "dbt_schedule" {
  description = "Cron schedule for dbt transformations"
  value       = var.dbt_schedule
}

output "dbt_service_account_email" {
  description = "Service account email for dbt jobs"
  value       = try(google_service_account.dbt_runner.email, null)
}

output "dbt_status_check" {
  description = "How to check dbt job status"
  value       = "gcloud scheduler jobs describe dev-nexus-${var.environment}-dbt --location ${var.region}"
}

# ====================================
# VPC Egress Outputs (New Module)
# ====================================

output "vpc_egress_info" {
  description = "VPC egress configuration summary"
  value = {
    vpc_name           = module.vpc_egress.vpc_name
    vpc_id             = module.vpc_egress.vpc_id
    subnet_cidr        = module.vpc_egress.subnet_cidrs[0]
    nat_gateway_ip     = module.vpc_egress.nat_gateway_ip
    router_name        = module.vpc_egress.router_id
  }
}

# ====================================
# PostgreSQL v2 Outputs (New Module)
# ====================================

output "postgres_v2_info" {
  description = "PostgreSQL v2.0.0 configuration summary"
  value = {
    instance_name      = module.postgres.postgres_instance_name
    internal_ip        = module.postgres.postgres_internal_ip
    zone               = module.postgres.postgres_zone
    database           = "pattern_discovery"
    version            = "16"
    pgvector_enabled   = true
  }
}
