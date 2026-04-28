# =============================================================================
# VPC Egress Module - New Architecture using gcp-vpc-egress-terraform v1.0.0
# =============================================================================
# Creates VPC, Router, NAT, and Firewall rules for clean egress setup
# Replaces the old vpc_module.tf and its issues
# =============================================================================

module "vpc_egress" {
  source = "git::https://github.com/DarojaAI/gcp-vpc-egress-terraform.git//terraform?ref=v1.0.0"

  project_id  = var.project_id
  region      = var.region
  environment = var.environment

  # VPC naming - will create: dev-nexus-prod-vpc
  vpc_name = "dev-nexus-${var.environment}-vpc"

  # Subnet configuration
  subnets = [
    {
      name = "main"
      cidr = "10.8.0.0/24"  # Same as before for stability
    }
  ]

  # Firewall rules
  allow_ssh_from_cidrs          = []  # No SSH needed from internet (use IAP)
  allow_postgres_from_cidrs     = []  # Internal only
  allow_github_actions_from_cidrs = concat(
    jsondecode(data.http.github_actions_ips.response_body).actions,
    ["0.0.0.0/0"]  # Allow all for dbt runs from Cloud Run
  )

  # Cloud NAT for egress (GitHub, PyPI, etc)
  enable_cloud_nat = true

  # Cloud Router for managed NAT
  router_name = "dev-nexus-${var.environment}-router"

  tags = merge(
    var.labels,
    {
      "vpc-version" = "1.0.0"
      "module"      = "vpc-egress"
    }
  )
}

# Fetch GitHub Actions runner IPs for firewall allowlisting
data "http" "github_actions_ips" {
  url = "https://api.github.com/meta"
  request_headers = {
    Accept = "application/vnd.github+json"
  }
}

# =============================================================================
# Outputs
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
  value       = module.vpc_egress.subnet_ids[0]
}

output "subnet_cidr" {
  description = "Subnet CIDR range"
  value       = module.vpc_egress.subnet_cidrs[0]
}

output "vpc_connector_path" {
  description = "Full VPC connector path for Cloud Run (if applicable)"
  value       = try(module.vpc_egress.vpc_connector_path, null)
}

output "nat_gateway_ip" {
  description = "NAT gateway external IP"
  value       = module.vpc_egress.nat_gateway_ip
}

output "router_id" {
  description = "Cloud Router ID"
  value       = module.vpc_egress.router_id
}
