# =============================================================================
# PostgreSQL Module Reference
# =============================================================================
# This file replaces the inline PostgreSQL setup with a reference to the
# shared gcp-postgres-terraform module.
#
# PREVIOUS: All PostgreSQL resources were defined inline in this file
# CURRENT: Uses gcp-postgres-terraform module (see backup/ directory)
#
# Benefits:
# - Single source of truth for PostgreSQL setup across all repos
# - GitHub Actions IP filtering built into the module
# - VPC setup via vpc-infra module
# - Easier maintenance and updates
#
# To recover inline setup: restore from backup/postgres.tf
# =============================================================================

# Import shared PostgreSQL module from gcp-postgres-terraform
# This module handles:
# - VPC network creation (or uses existing via vpc_name/subnet_name)
# - PostgreSQL VM on Compute Engine with pgvector
# - Firewall rules with GitHub Actions IP filtering built-in
# - Cloud NAT, VPC connector, backups, monitoring
module "postgres" {
  # Use the version with GitHub Actions firewall fix
  source = "github.com/DarojaAI/gcp-postgres-terraform//terraform?ref=v1.11"

  # Required inputs
  project_id          = var.project_id
  postgres_db_password = var.postgres_db_password
  instance_name        = "dev-nexus-pg"
  repo_prefix         = "dev-nexus"
  environment         = var.environment

  # Use existing VPC from current setup to avoid recreation
  vpc_name    = "dev-nexus-network"
  subnet_name = "dev-nexus-subnet"

  # PostgreSQL configuration
  postgres_version = var.postgres_version
  postgres_db_name = "pattern_discovery"
  postgres_db_user = "app_user"
  machine_type    = var.postgres_machine_type

  # Region
  region = var.region

  # GitHub Actions integration (enables firewall IP filtering)
  github_actions_enabled = var.github_actions_enabled
  github_repo            = var.github_repo
  github_owner          = var.github_owner
}

# =============================================================================
# PostgreSQL Outputs (forwarded from module)
# =============================================================================
# Keep the same output names as the previous inline setup for compatibility

output "postgres_internal_ip" {
  description = "Internal IP address of PostgreSQL VM"
  value       = module.postgres.internal_ip
}

output "postgres_external_ip" {
  description = "External IP address of PostgreSQL VM"
  value       = module.postgres.external_ip
}

output "postgres_instance_name" {
  description = "Name of the PostgreSQL VM instance"
  value       = module.postgres.instance_name
}

output "postgres_zone" {
  description = "Zone where PostgreSQL VM is deployed"
  value       = module.postgres.zone
}

output "postgres_connection_string_internal" {
  description = "PostgreSQL connection string for Cloud Run (internal VPC)"
  value       = module.postgres.connection_string_internal
}

output "postgres_connection_string_external" {
  description = "PostgreSQL connection string for external access"
  value       = module.postgres.connection_string_external
}

output "postgres_vpc_connector_name" {
  description = "Name of the VPC Access connector"
  value       = module.postgres.vpc_connector_name
}

output "postgres_vpc_connector_cidr" {
  description = "CIDR range of the VPC Access connector"
  value       = module.postgres.vpc_connector_cidr
}

output "postgres_secrets" {
  description = "Secret Manager secret IDs for PostgreSQL credentials"
  value       = module.postgres.secrets
}