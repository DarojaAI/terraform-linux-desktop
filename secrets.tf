# ============================================
# Secret Manager for PostgreSQL Credentials
# ============================================

# These secrets store connection info for PostgreSQL
# The values are managed by terraform and updated via CI/CD

resource "google_secret_manager_secret" "postgres_password" {
  secret_id = "${var.secret_prefix}-postgres-password"

  replication {
    auto {}
  }

  labels = var.labels

  depends_on = [google_project_service.secretmanager]
}

# Secret version managed via Terraform variable
resource "google_secret_manager_secret_version" "postgres_password" {
  secret      = google_secret_manager_secret.postgres_password.id
  secret_data = var.postgres_db_password
}

# Data source to read the password
data "google_secret_manager_secret_version" "postgres_password" {
  secret = google_secret_manager_secret.postgres_password.id
  depends_on = [
    google_secret_manager_secret_version.postgres_password
  ]
}

resource "google_secret_manager_secret" "postgres_user" {
  secret_id = "${var.secret_prefix}-postgres-user"

  replication {
    auto {}
  }

  labels = var.labels

  depends_on = [google_project_service.secretmanager]
}

# Version for postgres_user
resource "google_secret_manager_secret_version" "postgres_user" {
  secret      = google_secret_manager_secret.postgres_user.id
  secret_data = var.postgres_db_user
}

resource "google_secret_manager_secret" "postgres_db" {
  secret_id = "${var.secret_prefix}-postgres-db"

  replication {
    auto {}
  }

  labels = var.labels

  depends_on = [google_project_service.secretmanager]
}

# Version for postgres_db
resource "google_secret_manager_secret_version" "postgres_db" {
  secret      = google_secret_manager_secret.postgres_db.id
  secret_data = var.postgres_db_name
}

# Store PostgreSQL host IP in Secret Manager
# This ensures Cloud Run always gets the correct internal IP
resource "google_secret_manager_secret" "postgres_host" {
  secret_id = "${var.secret_prefix}-postgres-host"

  replication {
    auto {}
  }

  labels = var.labels

  depends_on = [google_project_service.secretmanager]
}

# Version for postgres_host (internal IP from module)
resource "google_secret_manager_secret_version" "postgres_host" {
  secret      = google_secret_manager_secret.postgres_host.id
  secret_data = module.postgres.internal_ip
}

# ============================================
# Secret IAM Bindings
# ============================================

resource "google_secret_manager_secret_iam_member" "postgres_password_access" {
  secret_id = google_secret_manager_secret.postgres_password.id
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${module.postgres.service_account_email}"
}

# Grant Cloud Run (default service account) access to read postgres credentials
resource "google_secret_manager_secret_iam_member" "cloudrun_postgres_password_access" {
  secret_id = google_secret_manager_secret.postgres_password.id
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${data.google_compute_default_service_account.default.email}"
}

resource "google_secret_manager_secret_iam_member" "cloudrun_postgres_user_access" {
  secret_id = google_secret_manager_secret.postgres_user.id
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${data.google_compute_default_service_account.default.email}"
}

resource "google_secret_manager_secret_iam_member" "cloudrun_postgres_db_access" {
  secret_id = google_secret_manager_secret.postgres_db.id
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${data.google_compute_default_service_account.default.email}"
}

resource "google_secret_manager_secret_iam_member" "cloudrun_postgres_host_access" {
  secret_id = google_secret_manager_secret.postgres_host.id
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${data.google_compute_default_service_account.default.email}"
}
