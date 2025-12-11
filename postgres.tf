# PostgreSQL Database VM with pgvector for Pattern Discovery Agent
# Deployed on GCP Compute Engine e2-micro (FREE tier eligible)

# Enable required APIs
resource "google_project_service" "compute" {
  service            = "compute.googleapis.com"
  disable_on_destroy = false
}

resource "google_project_service" "servicenetworking" {
  service            = "servicenetworking.googleapis.com"
  disable_on_destroy = false
}

resource "google_project_service" "vpcaccess" {
  service            = "vpcaccess.googleapis.com"
  disable_on_destroy = false
}

# ============================================
# VPC Network for PostgreSQL
# ============================================

# Create VPC network
resource "google_compute_network" "postgres_network" {
  name                    = "dev-nexus-network"
  auto_create_subnetworks = false
  depends_on              = [google_project_service.compute]
}

# Create subnet for PostgreSQL
resource "google_compute_subnetwork" "postgres_subnet" {
  name          = "dev-nexus-subnet"
  ip_cidr_range = var.postgres_subnet_cidr
  region        = var.region
  network       = google_compute_network.postgres_network.id

  log_config {
    aggregation_interval = "INTERVAL_10_MIN"
    flow_sampling        = 0.5
    metadata             = "INCLUDE_ALL_METADATA"
  }
}

# Firewall rule: Allow PostgreSQL from Cloud Run (via VPC connector)
resource "google_compute_firewall" "allow_postgres" {
  name    = "dev-nexus-allow-postgres"
  network = google_compute_network.postgres_network.name

  allow {
    protocol = "tcp"
    ports    = ["5432"]
  }

  source_ranges = [var.postgres_subnet_cidr]
  target_tags   = ["postgres-server"]
}

# Firewall rule: Allow SSH for maintenance
resource "google_compute_firewall" "allow_ssh" {
  name    = "dev-nexus-allow-ssh"
  network = google_compute_network.postgres_network.name

  allow {
    protocol = "tcp"
    ports    = ["22"]
  }

  source_ranges = var.allow_ssh_from_cidrs
  target_tags   = ["postgres-server"]
}

# VPC Connector for Cloud Run to access PostgreSQL
resource "google_vpc_access_connector" "postgres_connector" {
  name          = "dev-nexus-connector"
  region        = var.region
  network       = google_compute_network.postgres_network.name
  ip_cidr_range = var.vpc_connector_cidr
  min_instances = 2
  max_instances = 3

  depends_on = [
    google_project_service.vpcaccess,
    google_compute_subnetwork.postgres_subnet
  ]
}

# ============================================
# Cloud Storage for Backups
# ============================================

# Create bucket for PostgreSQL backups
resource "google_storage_bucket" "postgres_backups" {
  name          = "${var.project_id}-postgres-backups"
  location      = var.region
  force_destroy = false

  versioning {
    enabled = true
  }

  lifecycle_rule {
    condition {
      age = var.backup_retention_days
    }
    action {
      type = "Delete"
    }
  }

  lifecycle_rule {
    condition {
      num_newer_versions = 3
    }
    action {
      type = "Delete"
    }
  }

  uniform_bucket_level_access = true
}

# ============================================
# PostgreSQL VM Instance
# ============================================

# Create static IP for PostgreSQL
resource "google_compute_address" "postgres_ip" {
  name         = "dev-nexus-postgres-ip"
  address_type = "INTERNAL"
  subnetwork   = google_compute_subnetwork.postgres_subnet.id
  region       = var.region
}

# Startup script for PostgreSQL with pgvector
resource "google_compute_instance" "postgres" {
  name         = "dev-nexus-postgres"
  machine_type = var.postgres_machine_type
  zone         = "${var.region}-a"

  tags = ["postgres-server"]

  boot_disk {
    initialize_params {
      image = "ubuntu-os-cloud/ubuntu-2204-lts"
      size  = var.postgres_disk_size_gb
      type  = "pd-standard"
    }
  }

  network_interface {
    subnetwork = google_compute_subnetwork.postgres_subnet.id
    network_ip = google_compute_address.postgres_ip.address
  }

  metadata = {
    enable-oslogin = "TRUE"
  }

  metadata_startup_script = templatefile("${path.module}/scripts/postgres_init.sh", {
    db_name           = var.postgres_db_name
    db_user           = var.postgres_db_user
    db_password       = var.postgres_db_password
    backup_bucket     = google_storage_bucket.postgres_backups.name
    postgres_version  = var.postgres_version
    enable_monitoring = var.enable_postgres_monitoring
  })

  service_account {
    email  = google_service_account.postgres_vm.email
    scopes = ["cloud-platform"]
  }

  scheduling {
    automatic_restart   = true
    on_host_maintenance = "MIGRATE"
    preemptible         = false
  }

  # Ensure VM stays within free tier limits (if using e2-micro)
  allow_stopping_for_update = true

  labels = merge(var.labels, {
    component = "database"
    database  = "postgresql"
  })

  depends_on = [
    google_project_service.compute,
    google_compute_subnetwork.postgres_subnet,
    google_storage_bucket.postgres_backups
  ]
}

# ============================================
# Service Account for PostgreSQL VM
# ============================================

resource "google_service_account" "postgres_vm" {
  account_id   = "dev-nexus-postgres-vm"
  display_name = "Dev Nexus PostgreSQL VM"
  description  = "Service account for PostgreSQL VM with backup access"
}

# Grant access to write backups to Cloud Storage
resource "google_storage_bucket_iam_member" "postgres_backup_writer" {
  bucket = google_storage_bucket.postgres_backups.name
  role   = "roles/storage.objectCreator"
  member = "serviceAccount:${google_service_account.postgres_vm.email}"
}

# Grant access to read backups (for restore)
resource "google_storage_bucket_iam_member" "postgres_backup_reader" {
  bucket = google_storage_bucket.postgres_backups.name
  role   = "roles/storage.objectViewer"
  member = "serviceAccount:${google_service_account.postgres_vm.email}"
}

# Grant Secret Manager access for database credentials
resource "google_secret_manager_secret" "postgres_password" {
  secret_id = "POSTGRES_PASSWORD"

  replication {
    auto {}
  }

  depends_on = [google_project_service.secretmanager]
}

resource "google_secret_manager_secret_version" "postgres_password" {
  secret      = google_secret_manager_secret.postgres_password.id
  secret_data = var.postgres_db_password
}

resource "google_secret_manager_secret_iam_member" "postgres_password_access" {
  secret_id = google_secret_manager_secret.postgres_password.id
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${google_service_account.postgres_vm.email}"
}

# Grant Cloud Run access to read postgres password
resource "google_secret_manager_secret_iam_member" "cloudrun_postgres_password_access" {
  secret_id = google_secret_manager_secret.postgres_password.id
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${data.google_compute_default_service_account.default.email}"
}

# ============================================
# Monitoring and Alerting (Optional)
# ============================================

# Cloud Monitoring Dashboard for PostgreSQL
resource "google_monitoring_dashboard" "postgres" {
  count = var.enable_postgres_monitoring ? 1 : 0

  dashboard_json = jsonencode({
    displayName = "Dev Nexus PostgreSQL Dashboard"
    mosaicLayout = {
      columns = 12
      tiles = [
        {
          width  = 6
          height = 4
          widget = {
            title = "CPU Utilization"
            xyChart = {
              dataSets = [{
                timeSeriesQuery = {
                  timeSeriesFilter = {
                    filter = "resource.type=\"gce_instance\" AND resource.labels.instance_id=\"${google_compute_instance.postgres.instance_id}\""
                    aggregation = {
                      alignmentPeriod  = "60s"
                      perSeriesAligner = "ALIGN_MEAN"
                    }
                  }
                }
              }]
            }
          }
        }
      ]
    }
  })
}

# Alert policy for disk usage
resource "google_monitoring_alert_policy" "postgres_disk_usage" {
  count        = var.enable_postgres_monitoring ? 1 : 0
  display_name = "PostgreSQL Disk Usage High"
  combiner     = "OR"

  conditions {
    display_name = "Disk usage > 80%"

    condition_threshold {
      filter          = "resource.type=\"gce_instance\" AND resource.labels.instance_id=\"${google_compute_instance.postgres.instance_id}\""
      duration        = "300s"
      comparison      = "COMPARISON_GT"
      threshold_value = 80

      aggregations {
        alignment_period   = "60s"
        per_series_aligner = "ALIGN_MEAN"
      }
    }
  }

  notification_channels = var.alert_notification_channels

  alert_strategy {
    auto_close = "86400s" # 24 hours
  }
}
