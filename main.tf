# Terraform Configuration for dev-nexus Pattern Discovery Agent
# Deploys to Google Cloud Run with all required infrastructure

terraform {
  required_version = ">= 1.0"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 5.0"
    }
  }

  # Recommended: Use Cloud Storage backend for state
  # backend "gcs" {
  #   bucket = "your-terraform-state-bucket"
  #   prefix = "dev-nexus"
  # }
}

# Configure Google Cloud Provider
provider "google" {
  project = var.project_id
  region  = var.region
}

# Enable required APIs
resource "google_project_service" "run" {
  service            = "run.googleapis.com"
  disable_on_destroy = false
}

resource "google_project_service" "cloudbuild" {
  service            = "cloudbuild.googleapis.com"
  disable_on_destroy = false
}

resource "google_project_service" "secretmanager" {
  service            = "secretmanager.googleapis.com"
  disable_on_destroy = false
}

resource "google_project_service" "artifactregistry" {
  service            = "artifactregistry.googleapis.com"
  disable_on_destroy = false
}

# Create secrets in Secret Manager
resource "google_secret_manager_secret" "github_token" {
  secret_id = "GITHUB_TOKEN"

  replication {
    auto {}
  }

  depends_on = [google_project_service.secretmanager]
}

resource "google_secret_manager_secret_version" "github_token" {
  secret      = google_secret_manager_secret.github_token.id
  secret_data = var.github_token
}

resource "google_secret_manager_secret" "anthropic_api_key" {
  secret_id = "ANTHROPIC_API_KEY"

  replication {
    auto {}
  }

  depends_on = [google_project_service.secretmanager]
}

resource "google_secret_manager_secret_version" "anthropic_api_key" {
  secret      = google_secret_manager_secret.anthropic_api_key.id
  secret_data = var.anthropic_api_key
}

# Grant Cloud Run service account access to secrets
resource "google_secret_manager_secret_iam_member" "github_token_access" {
  secret_id = google_secret_manager_secret.github_token.id
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${data.google_project.project.number}-compute@developer.gserviceaccount.com"
}

resource "google_secret_manager_secret_iam_member" "anthropic_key_access" {
  secret_id = google_secret_manager_secret.anthropic_api_key.id
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${data.google_project.project.number}-compute@developer.gserviceaccount.com"
}

# Build and push Docker image to Artifact Registry
resource "null_resource" "docker_build" {
  triggers = {
    # Rebuild if source code changes
    src_hash = sha256(join("", [
      for f in fileset(path.module, "../{a2a,core,schemas}/**/*.py") : filesha256("${path.module}/${f}")
    ]))
    dockerfile_hash = filesha256("${path.module}/../Dockerfile")
  }

  provisioner "local-exec" {
    command = <<-EOT
      cd ${path.module}/..
      gcloud builds submit \
        --config=cloudbuild.yaml \
        --substitutions="_REGION=${var.region},_KNOWLEDGE_BASE_REPO=${var.knowledge_base_repo}" \
        --project=${var.project_id}
    EOT
  }

  depends_on = [
    google_project_service.cloudbuild,
    google_project_service.run
  ]
}

# Deploy Cloud Run service
resource "google_cloud_run_v2_service" "pattern_discovery_agent" {
  name     = "pattern-discovery-agent"
  location = var.region
  ingress  = var.allow_unauthenticated ? "INGRESS_TRAFFIC_ALL" : "INGRESS_TRAFFIC_INTERNAL_LOAD_BALANCER"

  template {
    scaling {
      min_instance_count = var.min_instances
      max_instance_count = var.max_instances
    }

    timeout = "${var.timeout_seconds}s"

    # VPC connector for PostgreSQL access
    vpc_access {
      connector = google_vpc_access_connector.postgres_connector.id
      egress    = "PRIVATE_RANGES_ONLY"
    }

    containers {
      image = "gcr.io/${var.project_id}/pattern-discovery-agent:latest"

      ports {
        container_port = 8080
      }

      resources {
        limits = {
          cpu    = var.cpu
          memory = var.memory
        }

        cpu_idle = var.cpu_always_allocated
      }

      env {
        name  = "GCP_PROJECT_ID"
        value = var.project_id
      }

      env {
        name  = "GCP_REGION"
        value = var.region
      }

      env {
        name  = "KNOWLEDGE_BASE_REPO"
        value = var.knowledge_base_repo
      }

      env {
        name  = "ALLOWED_SERVICE_ACCOUNTS"
        value = join(",", var.allowed_service_accounts)
      }

      env {
        name  = "REQUIRE_AUTH_FOR_WRITE"
        value = tostring(var.require_auth_for_write)
      }

      env {
        name = "GITHUB_TOKEN"
        value_source {
          secret_key_ref {
            secret  = google_secret_manager_secret.github_token.secret_id
            version = "latest"
          }
        }
      }

      env {
        name = "ANTHROPIC_API_KEY"
        value_source {
          secret_key_ref {
            secret  = google_secret_manager_secret.anthropic_api_key.secret_id
            version = "latest"
          }
        }
      }

      # PostgreSQL connection settings
      env {
        name  = "DATABASE_URL"
        value = "postgresql://${var.postgres_db_user}@${google_compute_address.postgres_ip.address}:5432/${var.postgres_db_name}"
      }

      env {
        name  = "POSTGRES_HOST"
        value = google_compute_address.postgres_ip.address
      }

      env {
        name  = "POSTGRES_PORT"
        value = "5432"
      }

      env {
        name  = "POSTGRES_DB"
        value = var.postgres_db_name
      }

      env {
        name  = "POSTGRES_USER"
        value = var.postgres_db_user
      }

      env {
        name = "POSTGRES_PASSWORD"
        value_source {
          secret_key_ref {
            secret  = google_secret_manager_secret.postgres_password.secret_id
            version = "latest"
          }
        }
      }

      env {
        name  = "USE_POSTGRESQL"
        value = "true"
      }

      env {
        name  = "ALLOWED_ORIGIN_REGEX"
        value = var.allowed_origin_regex
      }

      # Optional: External agent URLs
      dynamic "env" {
        for_each = var.orchestrator_url != "" ? [1] : []
        content {
          name  = "ORCHESTRATOR_URL"
          value = var.orchestrator_url
        }
      }

      dynamic "env" {
        for_each = var.log_attacker_url != "" ? [1] : []
        content {
          name  = "LOG_ATTACKER_URL"
          value = var.log_attacker_url
        }
      }
    }

    service_account = data.google_compute_default_service_account.default.email
  }

  traffic {
    type    = "TRAFFIC_TARGET_ALLOCATION_TYPE_LATEST"
    percent = 100
  }

  depends_on = [
    null_resource.docker_build,
    google_secret_manager_secret_iam_member.github_token_access,
    google_secret_manager_secret_iam_member.anthropic_key_access
  ]
}

# Allow unauthenticated access (optional, for testing)
resource "google_cloud_run_service_iam_member" "public_access" {
  count = var.allow_unauthenticated ? 1 : 0

  location = google_cloud_run_v2_service.pattern_discovery_agent.location
  service  = google_cloud_run_v2_service.pattern_discovery_agent.name
  role     = "roles/run.invoker"
  member   = "allUsers"
}

# Create service accounts for external agents
resource "google_service_account" "log_attacker" {
  count = var.create_external_service_accounts ? 1 : 0

  account_id   = "log-attacker-client"
  display_name = "Agentic Log Attacker Client"
  description  = "Service account for agentic-log-attacker to call dev-nexus"
}

resource "google_service_account" "orchestrator" {
  count = var.create_external_service_accounts ? 1 : 0

  account_id   = "orchestrator-client"
  display_name = "Dependency Orchestrator Client"
  description  = "Service account for dependency-orchestrator to call dev-nexus"
}

# Grant external service accounts Cloud Run invoker permission
resource "google_cloud_run_service_iam_member" "log_attacker_invoker" {
  count = var.create_external_service_accounts ? 1 : 0

  location = google_cloud_run_v2_service.pattern_discovery_agent.location
  service  = google_cloud_run_v2_service.pattern_discovery_agent.name
  role     = "roles/run.invoker"
  member   = "serviceAccount:${google_service_account.log_attacker[0].email}"
}

resource "google_cloud_run_service_iam_member" "orchestrator_invoker" {
  count = var.create_external_service_accounts ? 1 : 0

  location = google_cloud_run_v2_service.pattern_discovery_agent.location
  service  = google_cloud_run_v2_service.pattern_discovery_agent.name
  role     = "roles/run.invoker"
  member   = "serviceAccount:${google_service_account.orchestrator[0].email}"
}

# Data sources
data "google_project" "project" {
  project_id = var.project_id
}

data "google_compute_default_service_account" "default" {}
