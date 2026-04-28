# =============================================================================
# dbt Module - Separate Scheduled Jobs using gcp-dbt-terraform v1.0.0
# =============================================================================
# Runs dbt transformations on schedule, independent from Cloud Run app.
# Connects to same PostgreSQL instance but executes separately and safely.
# =============================================================================

module "dbt" {
  source = "git::https://github.com/DarojaAI/gcp-dbt-terraform.git//terraform?ref=v1.0.0"

  project_id = var.project_id
  region     = var.region

  # VPC Configuration - use same VPC as PostgreSQL
  vpc_network_id = module.vpc_egress.vpc_id
  vpc_name       = module.vpc_egress.vpc_name

  # Service naming
  service_name = "dev-nexus-${var.environment}-dbt"

  # Container image (dbt CLI image)
  dbt_image = "ghcr.io/dbt-labs/dbt-postgres:1.7.0"

  # PostgreSQL Connection
  postgres_host     = module.postgres.postgres_internal_ip
  postgres_port     = 5432
  postgres_database = "pattern_discovery"
  postgres_user     = "app_user"
  postgres_password = var.postgres_db_password

  # dbt Configuration
  dbt_project_dir = "/app"
  dbt_profiles_dir = "/app/profiles"

  # dbt commands - runs transforms on schedule
  dbt_commands = [
    "dbt deps --profiles-dir=/app/profiles",
    "dbt seed --profiles-dir=/app/profiles",
    "dbt run --profiles-dir=/app/profiles",
    "dbt test --profiles-dir=/app/profiles"
  ]

  # Scheduling
  schedule_expression = var.dbt_schedule  # e.g., "0 2 * * *" for 2 AM daily UTC
  timezone            = "UTC"

  # Resource limits
  memory_mb = 1024
  cpu       = 2

  # Execution timeout
  timeout_seconds = 3600  # 1 hour max for dbt runs

  # Environment variables
  environment_variables = {
    DBT_PROFILES_DIR  = "/app/profiles"
    DBT_PROJECT_DIR   = "/app"
    POSTGRES_SCHEMA   = "public"
    POSTGRES_THREADS  = "4"
  }

  # GitHub Actions integration (for dbt Cloud lookups if needed)
  github_token_secret_name = "github-token"

  # Monitoring and alerts
  enable_monitoring = true
  alert_email       = var.monitoring_alert_email
  
  # Failure notification
  failure_notification_channel = var.failure_notification_channel  # e.g., Slack webhook

  # Logging
  enable_detailed_logging = true
  log_retention_days      = 30

  # Labels
  labels = merge(
    var.labels,
    {
      "dbt-version"  = "1.7.0"
      "module"       = "dbt"
      "environment"  = var.environment
      "schedule"     = "daily"
    }
  )

  depends_on = [
    module.vpc_egress,
    module.postgres
  ]
}

# =============================================================================
# dbt Cloud Run Service Account
# =============================================================================
# Service account for dbt Cloud Run job to access PostgreSQL

resource "google_service_account" "dbt_runner" {
  account_id   = "dev-nexus-${var.environment}-dbt"
  display_name = "dbt transformer for dev-nexus ${var.environment}"
}

# Grant Cloud Run invoke permission to Cloud Scheduler
resource "google_cloud_run_service_iam_member" "dbt_scheduler_invoke" {
  service  = module.dbt.service_name
  location = var.region
  role     = "roles/run.invoker"
  member   = "serviceAccount:${google_service_account.dbt_runner.email}"
}

# Allow dbt service account to access secrets
resource "google_secret_manager_secret_iam_member" "dbt_postgres_password" {
  secret_id = google_secret_manager_secret.postgres_password.id
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${google_service_account.dbt_runner.email}"
}

resource "google_secret_manager_secret_iam_member" "dbt_github_token" {
  secret_id = "github-token"
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${google_service_account.dbt_runner.email}"
}

# =============================================================================
# Outputs
# =============================================================================

output "dbt_service_name" {
  description = "dbt Cloud Run service name"
  value       = module.dbt.service_name
}

output "dbt_service_url" {
  description = "dbt Cloud Run service URL"
  value       = module.dbt.service_url
}

output "dbt_scheduler_job_id" {
  description = "Cloud Scheduler job ID for dbt"
  value       = module.dbt.scheduler_job_id
}

output "dbt_scheduler_expression" {
  description = "Cron expression for dbt schedule"
  value       = var.dbt_schedule
}

output "dbt_service_account_email" {
  description = "Service account email for dbt jobs"
  value       = google_service_account.dbt_runner.email
}

output "dbt_last_run_time" {
  description = "Timestamp of last dbt run (from Cloud Scheduler)"
  value       = module.dbt.last_execution_time
}

output "dbt_next_run_time" {
  description = "Timestamp of next scheduled dbt run"
  value       = module.dbt.next_execution_time
}
