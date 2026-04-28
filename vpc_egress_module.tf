# =============================================================================
# VPC Egress Module - Using gcp-vpc-egress-terraform (fix/allow-postgres-default branch)
# =============================================================================
# Creates VPC, subnets, Cloud Router, Cloud NAT, and Firewall rules
# for clean egress setup and Cloud Run connectivity
# =============================================================================

module "vpc_egress" {
  # Using fix/allow-postgres-default branch which sets allow_postgres=false by default
  # This avoids firewall tag conflicts when used with gcp-postgres-terraform
  source = "git::https://github.com/DarojaAI/gcp-vpc-egress-terraform.git//terraform?ref=fix/allow-postgres-default"

  project_id  = var.project_id
  region      = var.region
  environment = var.environment

  # VPC naming
  vpc_name = "dev-nexus-${var.environment}-vpc"

  # Subnet configuration - gcp-vpc-egress-terraform creates a single subnet
  subnet_name = "main"
  subnet_cidr = "10.8.0.0/24" # Same as before for stability

  # Firewall rules
  allow_ssh            = false # No SSH from internet (use IAP)
  allow_ssh_from_cidrs = []
  # NOTE: allow_postgres defaults to false in fix/allow-postgres-default branch
  # Postgres module creates its own firewall rules to avoid tag conflicts

  # VPC Flow Logs
  enable_flow_logs   = true
  flow_sampling      = 0.5
  log_config_enabled = true

  # Tags
  tags = var.labels
}

# =============================================================================
# VPC Access Connector for Cloud Run
# =============================================================================
# The gcp-vpc-egress-terraform module doesn't create VPC Access Connector,
# so we create it here for Cloud Run to reach PostgreSQL

resource "google_vpc_access_connector" "cloud_run" {
  name          = "dev-nexus-${var.environment}-connector"
  region        = var.region
  network       = module.vpc_egress.vpc_name
  ip_cidr_range = var.vpc_connector_cidr
  min_instances = 2
  max_instances = 10

  depends_on = [module.vpc_egress]
}

# =============================================================================
# Outputs - VPC Connectivity Info
# =============================================================================

output "vpc_id" {
  description = "VPC ID for use in other modules"
  value       = module.vpc_egress.vpc_id
}

output "vpc_name" {
  description = "VPC name"
  value       = module.vpc_egress.vpc_name
}

output "subnet_id" {
  description = "Subnet ID for PostgreSQL VM"
  value       = module.vpc_egress.subnet_id
}

output "subnet_cidr" {
  description = "Subnet CIDR range"
  value       = module.vpc_egress.subnet_cidr
}

output "nat_name" {
  description = "Cloud NAT gateway name"
  value       = module.vpc_egress.nat_name
}

output "router_id" {
  description = "Cloud Router ID"
  value       = module.vpc_egress.router_id
}

# NOTE: VPC connector outputs defined in outputs.tf
