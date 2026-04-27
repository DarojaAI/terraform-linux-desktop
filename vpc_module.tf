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
  source = "github.com/DarojaAI/vpc-infra//terraform?ref=v1.0.5"

  project_id  = var.project_id
  region      = var.region
  environment = var.environment

  # VPC naming with environment suffix (short to stay within 25-char limit for connector)
  vpc_name = "dev-nexus-${var.environment}"

  # Subnets (names are appended to vpc_name)
  subnets = [
    {
      name = "main"
      cidr = "10.8.0.0/24"
    }
  ]

  # Allow SSH from internal ranges only
  allow_ssh_from_cidrs = []

  # Enable Cloud NAT for outbound connectivity
  enable_cloud_nat = true
}
