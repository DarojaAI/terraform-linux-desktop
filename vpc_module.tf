# =============================================================================
# VPC Infrastructure Module
# =============================================================================
# Calls the shared vpc-infra module to create VPC network, subnets,
# Cloud NAT, and VPC Access Connector for Cloud Run / GitHub Actions.
#
# This ensures consistent VPC setup across all projects and delegates
# networking concerns to a dedicated module.
# =============================================================================

module "vpc" {
  source = "github.com/DarojaAI/vpc-infra//terraform?ref=v1.0.3"

  project_id  = var.project_id
  region      = var.region
  environment = var.environment

  # VPC naming with environment suffix
  vpc_name = "dev-nexus-network-${var.environment}"

  # Subnets
  subnets = [
    {
      name = "dev-nexus-subnet-${var.environment}"
      cidr = "10.8.0.0/24"
    }
  ]

  # Allow SSH from internal ranges only
  allow_ssh_from_cidrs = []

  # Enable Cloud NAT for outbound connectivity
  enable_cloud_nat = true
}
