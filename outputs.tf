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
    health_check = "curl ${google_cloud_run_v2_service.pattern_discovery_agent.uri}/health"
    agentcard    = "curl ${google_cloud_run_v2_service.pattern_discovery_agent.uri}/.well-known/agent.json | jq"
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
        DEV_NEXUS_URL                 = google_cloud_run_v2_service.pattern_discovery_agent.uri
        DEVNEXUS_INTEGRATION_ENABLED  = "true"
      }
    }
    orchestrator = {
      service_account = google_service_account.orchestrator[0].email
      dev_nexus_url   = google_cloud_run_v2_service.pattern_discovery_agent.uri
      env_vars = {
        DEV_NEXUS_URL   = google_cloud_run_v2_service.pattern_discovery_agent.uri
      }
    }
  } : null
}

# ====================================
# PostgreSQL Outputs
# ====================================

output "postgres_internal_ip" {
  description = "Internal IP address of PostgreSQL VM"
  value       = google_compute_address.postgres_ip.address
}

output "postgres_instance_name" {
  description = "Name of the PostgreSQL VM instance"
  value       = google_compute_instance.postgres.name
}

output "postgres_zone" {
  description = "Zone where PostgreSQL VM is deployed"
  value       = google_compute_instance.postgres.zone
}

output "postgres_connection_string" {
  description = "PostgreSQL connection string (password redacted)"
  value       = "postgresql://${var.postgres_db_user}:****@${google_compute_address.postgres_ip.address}:5432/${var.postgres_db_name}"
  sensitive   = false
}

output "postgres_backup_bucket" {
  description = "Cloud Storage bucket for PostgreSQL backups"
  value       = google_storage_bucket.postgres_backups.name
}

output "vpc_connector_name" {
  description = "Name of the VPC connector for Cloud Run to PostgreSQL"
  value       = google_vpc_access_connector.postgres_connector.name
}

output "postgres_ssh_command" {
  description = "Command to SSH into PostgreSQL VM"
  value       = "gcloud compute ssh ${google_compute_instance.postgres.name} --zone=${google_compute_instance.postgres.zone} --project=${var.project_id}"
}

# ====================================
# Summary
# ====================================

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
    database_location = "${google_compute_instance.postgres.zone} (${google_compute_address.postgres_ip.address})"
    backup_bucket     = google_storage_bucket.postgres_backups.name
  }
}
