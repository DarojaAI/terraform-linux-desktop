# =============================================================================
# PostgreSQL Module v2 - Using gcp-postgres-terraform v4.0.2
# =============================================================================
# This module handles:
# - PostgreSQL VM on Compute Engine with pgvector
# - Firewall rules with GitHub Actions IP filtering
# - Backups, monitoring, and secret management
#
# VPC infrastructure is managed by vpc_egress module
# =============================================================================

module "postgres" {
  source = "git::https://github.com/DarojaAI/gcp-postgres-terraform.git//terraform?ref=v4.0.2"

  # Required inputs
  project_id           = var.project_id
  postgres_db_password = var.postgres_db_password
  instance_name        = "dev-nexus-pg"
  repo_prefix          = var.repo_nickname
  environment          = var.environment

  # Use existing VPC from vpc_egress module
  vpc_name    = module.vpc_egress.vpc_name
  subnet_name = module.vpc_egress.subnet_name
  network_id  = module.vpc_egress.vpc_id
  subnet_id   = module.vpc_egress.subnet_id
  subnet_cidr = module.vpc_egress.subnet_cidr

  # PostgreSQL configuration
  postgres_version = var.postgres_version
  postgres_db_name = "pattern_discovery"
  postgres_db_user = "app_user"
  machine_type     = local.env_contract.postgres_machine_type

  # Region
  region = var.region

  # VPC Connector configuration
  # When vpc_name is provided, postgres module doesn't create connector (outputs null)
  vpc_connector_cidr          = var.vpc_connector_cidr
  vpc_connector_min_instances = 2
  vpc_connector_max_instances = 10

  # SSH from internet disabled — use IAP tunnel for access
  allow_ssh_from_cidrs = []

  # Disable monitoring dashboard (causes IAM permission errors in CI/CD)
  enable_monitoring = false

  # Cloud NAT is managed by vpc_egress module, not postgres module.
  # Setting false prevents the postgres module's data source from looking up
  # nat-dev-nexus-prod-vpc at plan time (which fails when NAT doesn't exist yet).
  enable_cloud_nat = false

  # Depend on VPC module so it's created first
  depends_on = [module.vpc_egress]
}

# NOTE: postgres module creates its own vpc_connector when vpc_name is not passed
# Output reference: module.postgres.vpc_connector_name
