# =============================================================================
# PostgreSQL Module - New Architecture using gcp-postgres-terraform v2.0.0
# =============================================================================
# Refined PostgreSQL deployment with better startup scripts, SSH access,
# and health checks. Requires VPC from vpc_egress_module.tf
# =============================================================================

module "postgres" {
  source = "git::https://github.com/DarojaAI/gcp-postgres-terraform.git//terraform?ref=v2.0.0"

  project_id = var.project_id
  region     = var.region
  zone       = "${var.region}-b"

  # VPC Configuration - use output from vpc_egress module
  vpc_network_id = module.vpc_egress.vpc_id
  vpc_name       = module.vpc_egress.vpc_name
  subnet_id      = module.vpc_egress.subnet_id
  subnet_cidr    = module.vpc_egress.subnet_cidr

  # Instance Configuration
  instance_name = "dev-nexus-${var.environment}-postgres"
  machine_type  = var.postgres_machine_type  # e.g., "n1-standard-2"

  # PostgreSQL Configuration
  postgres_version   = "16"
  postgres_db_name   = "pattern_discovery"
  postgres_db_user   = "app_user"
  postgres_db_password = var.postgres_db_password

  # pgvector for embeddings
  pgvector_enabled = true

  # Performance tuning
  max_connections         = 100
  shared_buffers          = "256MB"
  work_mem                = "16MB"
  maintenance_work_mem    = "64MB"

  # Disk Configuration
  data_disk_size_gb = 100
  data_disk_type    = "pd-standard"

  # Backup Configuration
  enable_backups       = true
  backup_bucket_name   = "dev-nexus-${var.environment}-postgres-backups"
  backup_retention_days = 30

  # Monitoring
  enable_monitoring = true
  monitoring_alert_email = var.monitoring_alert_email

  # SSH Access - v2.0.0 includes proper firewall rules
  allow_ssh_from_cidrs = [module.vpc_egress.nat_gateway_ip]  # From Cloud NAT

  # Startup script logging
  log_file = "/var/log/postgres-setup.log"

  # Labels
  labels = merge(
    var.labels,
    {
      "postgres-version" = "16"
      "module"           = "postgres-v2"
      "environment"      = var.environment
    }
  )

  depends_on = [module.vpc_egress]
}

# =============================================================================
# Outputs
# =============================================================================

output "postgres_internal_ip" {
  description = "PostgreSQL internal IP address"
  value       = module.postgres.postgres_internal_ip
}

output "postgres_instance_name" {
  description = "PostgreSQL VM instance name"
  value       = module.postgres.postgres_instance_name
}

output "postgres_zone" {
  description = "PostgreSQL VM zone"
  value       = module.postgres.postgres_zone
}

output "postgres_connection_string_internal" {
  description = "PostgreSQL connection string for Cloud Run"
  value       = "postgresql://${var.postgres_db_user}:${var.postgres_db_password}@${module.postgres.postgres_internal_ip}:5432/${var.postgres_db_name}"
  sensitive   = true
}

output "postgres_external_ip" {
  description = "PostgreSQL external IP (if assigned)"
  value       = try(module.postgres.postgres_external_ip, null)
}

output "backup_bucket_name" {
  description = "GCS bucket for PostgreSQL backups"
  value       = module.postgres.backup_bucket_name
}

output "postgres_setup_log_location" {
  description = "Location of startup script logs on the VM"
  value       = "/var/log/postgres-setup.log"
  help        = "SSH into VM and run: tail -f /var/log/postgres-setup.log"
}
