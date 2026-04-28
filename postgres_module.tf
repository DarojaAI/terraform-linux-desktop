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
# - PostgreSQL VM on Compute Engine with pgvector
# - Firewall rules with GitHub Actions IP filtering built-in
# - Backups, monitoring, and secret management
#
# NOTE: VPC infrastructure (network, subnets, connectors) is managed by
# the vpc-infra module. We reference those outputs here to ensure consistent
# networking setup.
module "postgres" {
  # Use the version with GitHub Actions firewall fix
  source = "github.com/DarojaAI/gcp-postgres-terraform//terraform?ref=main"

  # Required inputs
  project_id           = var.project_id
  postgres_db_password = var.postgres_db_password
  instance_name        = "dev-nexus-pg"
  repo_prefix          = "dev-nexus"
  environment          = var.environment

  # Use existing VPC from vpc-infra module output
  vpc_name    = module.vpc.vpc_name
  subnet_name = module.vpc.subnet_names[0]

  # PostgreSQL configuration
  postgres_version = var.postgres_version
  postgres_db_name = "pattern_discovery"
  postgres_db_user = "app_user"
  machine_type     = var.postgres_machine_type

  # Region
  region = var.region

  # VPC Connector configuration for Cloud Run
  vpc_connector_cidr          = var.vpc_connector_cidr
  vpc_connector_min_instances = 2
  vpc_connector_max_instances = 10

  # NOTE: When using an external VPC (vpc_name provided), the postgres module
  # skips creating its own VPC connector and outputs null for vpc_connector_name.
  # Instead, we rely on the vpc-infra module to create the connector.
  # This will require a future update to gcp-postgres-terraform to accept and
  # output vpc_connector_name as an input parameter. For now, we'll use a local
  # reference to module.vpc.vpc_connector_name in main.tf.

  # Disable monitoring dashboard (causes IAM permission errors in CI/CD)
  enable_monitoring = false

  # Depend on VPC module so it's created first
  depends_on = [module.vpc]

  # NOTE: github_actions_backup_reader_sa is NOT set here.
  # The backup bucket IAM is handled manually as a one-time bootstrap step.
  # This avoids a circular dependency: terraform plan needs to read bucket IAM,
  # but the bucket's IAM can't be granted until terraform apply creates the bucket.
  # See gcp-postgres-terraform/docs/CI-CD-SETUP.md for the manual grant step.
}