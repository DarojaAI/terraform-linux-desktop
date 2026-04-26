# Terraform Configuration for dev-nexus Pattern Discovery Agent
# Deploys to Google Cloud Run with all required infrastructure

terraform {
  required_version = ">= 1.0"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 7.0"
    }
  }

  # Remote state: GCS bucket — always use this backend, never local state.
  # State is stored in: gs://globalbiting-dev-terraform-state/dev-nexus/<prefix>/
  backend "gcs" {
    bucket = "globalbiting-dev-terraform-state"
    prefix = "dev-nexus/dev"
  }
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

# Artifact Registry repository for Docker images
resource "google_artifact_registry_repository" "dev_nexus" {
  location      = var.region
  repository_id = "dev-nexus"
  format        = "DOCKER"

  depends_on = [google_project_service.artifactregistry]
}

# Grant GitHub Actions SA permission to push to Artifact Registry
resource "google_artifact_registry_repository_iam_member" "github_actions_writer" {
  location      = var.region
  repository    = google_artifact_registry_repository.dev_nexus.name
  role          = "roles/artifactregistry.writer"
  member        = "serviceAccount:github-actions-deploy@${var.project_id}.iam.gserviceaccount.com"
}

# Create secrets in Secret Manager (prefixed per environment to prevent collisions)
resource "google_secret_manager_secret" "github_token" {
  secret_id = "${var.secret_prefix}_GITHUB_TOKEN"

  replication {
    auto {}
  }

  labels = var.labels

  depends_on = [google_project_service.secretmanager]
}

# SecretVersion managed via Cloud Shell — see scripts/setup-gcp-secrets.sh

# GitHub OAuth secrets
resource "google_secret_manager_secret" "github_client_id" {
  secret_id = "${var.secret_prefix}_GITHUB_CLIENT_ID"

  replication {
    auto {}
  }

  labels = var.labels

  depends_on = [google_project_service.secretmanager]
}

# SecretVersion managed via Cloud Shell — see scripts/setup-gcp-secrets.sh

resource "google_secret_manager_secret" "github_client_secret" {
  secret_id = "${var.secret_prefix}_GITHUB_CLIENT_SECRET"

  replication {
    auto {}
  }

  labels = var.labels

  depends_on = [google_project_service.secretmanager]
}

# SecretVersion managed via Cloud Shell — see scripts/setup-gcp-secrets.sh

# JWT secret for token signing
resource "google_secret_manager_secret" "jwt_secret" {
  secret_id = "${var.secret_prefix}_JWT_SECRET"

  replication {
    auto {}
  }

  labels = var.labels

  depends_on = [google_project_service.secretmanager]
}

# SecretVersion managed via Cloud Shell — see scripts/setup-gcp-secrets.sh

resource "google_secret_manager_secret" "anthropic_api_key" {
  secret_id = "${var.secret_prefix}_ANTHROPIC_API_KEY"

  replication {
    auto {}
  }

  labels = var.labels

  depends_on = [google_project_service.secretmanager]
}

# SecretVersion managed via Cloud Shell — see scripts/setup-gcp-secrets.sh

# LangSmith API Key (optional - only created if API key is provided)
resource "google_secret_manager_secret" "langsmith_api_key" {
  count     = 1 # Always created (empty if not used)
  secret_id = "${var.secret_prefix}_LANGSMITH_API_KEY"

  replication {
    auto {}
  }

  labels = var.labels

  depends_on = [google_project_service.secretmanager]
}

# SecretVersion managed via Cloud Shell — see scripts/setup-gcp-secrets.sh

# External A2A Agent Tokens (always created with count=1 for state compatibility)
resource "google_secret_manager_secret" "pattern_miner_token" {
  count     = 1
  secret_id = "${var.secret_prefix}_PATTERN_MINER_TOKEN"

  replication {
    auto {}
  }

  labels = var.labels

  depends_on = [google_project_service.secretmanager]
}

# SecretVersion managed via Cloud Shell — see scripts/setup-gcp-secrets.sh

resource "google_secret_manager_secret" "action_agent_token" {
  count     = 1
  secret_id = "${var.secret_prefix}_ACTION_AGENT_TOKEN"

  replication {
    auto {}
  }

  labels = var.labels

  depends_on = [google_project_service.secretmanager]
}

# SecretVersion managed via Cloud Shell — see scripts/setup-gcp-secrets.sh

resource "google_secret_manager_secret_iam_member" "action_agent_token_access" {
  count     = 1
  secret_id = google_secret_manager_secret.action_agent_token[0].id
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${data.google_project.project.number}-compute@developer.gserviceaccount.com"
}

resource "google_secret_manager_secret" "orchestrator_token" {
  count     = 1
  secret_id = "${var.secret_prefix}_ORCHESTRATOR_TOKEN"

  replication {
    auto {}
  }

  labels = var.labels

  depends_on = [google_project_service.secretmanager]
}

# SecretVersion managed via Cloud Shell — see scripts/setup-gcp-secrets.sh

# Grant Cloud Run service account access to secrets
resource "google_secret_manager_secret_iam_member" "github_token_access" {
  secret_id = google_secret_manager_secret.github_token.id
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${data.google_project.project.number}-compute@developer.gserviceaccount.com"
}

resource "google_secret_manager_secret_iam_member" "github_client_id_access" {
  secret_id = google_secret_manager_secret.github_client_id.id
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${data.google_project.project.number}-compute@developer.gserviceaccount.com"
}

resource "google_secret_manager_secret_iam_member" "github_client_secret_access" {
  secret_id = google_secret_manager_secret.github_client_secret.id
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${data.google_project.project.number}-compute@developer.gserviceaccount.com"
}

resource "google_secret_manager_secret_iam_member" "jwt_secret_access" {
  secret_id = google_secret_manager_secret.jwt_secret.id
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${data.google_project.project.number}-compute@developer.gserviceaccount.com"
}

resource "google_secret_manager_secret_iam_member" "anthropic_key_access" {
  secret_id = google_secret_manager_secret.anthropic_api_key.id
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${data.google_project.project.number}-compute@developer.gserviceaccount.com"
}

resource "google_secret_manager_secret_iam_member" "langsmith_api_key_access" {
  count     = var.langsmith_api_key != "" ? 1 : 0
  secret_id = google_secret_manager_secret.langsmith_api_key[0].id
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${data.google_project.project.number}-compute@developer.gserviceaccount.com"
}

resource "google_secret_manager_secret_iam_member" "pattern_miner_token_access" {
  count     = var.pattern_miner_token != "" ? 1 : 0
  secret_id = google_secret_manager_secret.pattern_miner_token[0].id
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${data.google_project.project.number}-compute@developer.gserviceaccount.com"
}

resource "google_secret_manager_secret_iam_member" "orchestrator_token_access" {
  count     = var.orchestrator_token != "" ? 1 : 0
  secret_id = google_secret_manager_secret.orchestrator_token[0].id
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${data.google_project.project.number}-compute@developer.gserviceaccount.com"
}

# Build and push Docker image to Artifact Registry
# Note: Removed null_resource.docker_build as it conflicts with Terraform's
# google_cloud_run_v2_service deployment. Both were trying to deploy
# to the same Cloud Run service. Use separate docker build + push workflow
# if manual image rebuild is needed, or let Terraform handle everything.

# Deploy Cloud Run service
resource "google_cloud_run_v2_service" "pattern_discovery_agent" {
  name     = "pattern-discovery-agent"
  location = var.region
  ingress  = var.allow_unauthenticated ? "INGRESS_TRAFFIC_ALL" : "INGRESS_TRAFFIC_INTERNAL_LOAD_BALANCER"

  # Ensure all dependencies are ready before creating service
  depends_on = [
    module.vpc,
    module.postgres,
    google_secret_manager_secret_iam_member.github_token_access,
    google_secret_manager_secret_iam_member.anthropic_key_access,
    google_secret_manager_secret_iam_member.github_client_id_access,
    google_secret_manager_secret_iam_member.github_client_secret_access,
    google_secret_manager_secret_iam_member.jwt_secret_access,
    google_secret_manager_secret_iam_member.cloudrun_postgres_password_access,
    google_secret_manager_secret_iam_member.cloudrun_postgres_user_access,
    google_secret_manager_secret_iam_member.cloudrun_postgres_db_access,
    google_secret_manager_secret_iam_member.cloudrun_postgres_host_access
  ]

  template {
    scaling {
      min_instance_count = var.min_instances
      max_instance_count = var.max_instances
    }

    timeout = "${var.timeout_seconds}s"

    
    # Use VPC connector for PostgreSQL access
    vpc_access {
      connector = module.vpc.vpc_connector_name
      # Use PRIVATE_RANGES_ONLY so public internet traffic (GitHub OAuth) routes directly
      # from Cloud Run. "ALL_TRAFFIC" would break OAuth because the VPC connector's IP
      # range (10.10.2.0/28) isn't covered by Cloud NAT.
      egress    = "PRIVATE_RANGES_ONLY"
    }

    containers {
      image = "us-central1-docker.pkg.dev/${var.project_id}/dev-nexus/pattern-discovery-agent:latest"

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
      # NOTE: DATABASE_URL is NOT set here because it would expose the password in plain text
      # The app uses individual POSTGRES_* environment variables (POSTGRES_HOST, POSTGRES_USER, etc.)
      # which are properly set below. For audit.py which uses DATABASE_URL, it should fall back to
      # constructing the URL from individual vars or using the default. The database.py already
      # reads individual vars and constructs the connection properly.

      env {
        name = "POSTGRES_HOST"
        value_source {
          secret_key_ref {
            secret  = google_secret_manager_secret.postgres_host.secret_id
            # Use dynamic version from data source - triggers redeploy when secret updates
            version = data.google_secret_manager_secret_version.postgres_host.version
          }
        }
      }

      env {
        name  = "POSTGRES_PORT"
        value = "5432"
      }

      env {
        name = "POSTGRES_DB"
        value_source {
          secret_key_ref {
            secret  = google_secret_manager_secret.postgres_db.secret_id
            version = "latest"
          }
        }
      }

      env {
        name = "POSTGRES_USER"
        value_source {
          secret_key_ref {
            secret  = google_secret_manager_secret.postgres_user.secret_id
            version = "latest"
          }
        }
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
        name  = "POSTGRES_SSLMODE"
        value = "disable"
      }

      env {
        name  = "POSTGRES_SSL_NO_VERIFY"
        value = "false"
      }

      # GitHub OAuth configuration
      env {
        name = "GITHUB_CLIENT_ID"
        value_source {
          secret_key_ref {
            secret  = google_secret_manager_secret.github_client_id.secret_id
            version = "latest"
          }
        }
      }

      env {
        name = "GITHUB_CLIENT_SECRET"
        value_source {
          secret_key_ref {
            secret  = google_secret_manager_secret.github_client_secret.secret_id
            version = "latest"
          }
        }
      }

      env {
        name = "JWT_SECRET"
        value_source {
          secret_key_ref {
            secret  = google_secret_manager_secret.jwt_secret.secret_id
            version = "latest"
          }
        }
      }

      env {
        name  = "JWT_EXPIRE_HOURS"
        value = tostring(var.jwt_expire_hours)
      }

      # LangSmith Configuration (LLM Observability)
      env {
        name = "LANGSMITH_API_KEY"
        value_source {
          secret_key_ref {
            secret  = google_secret_manager_secret.langsmith_api_key[0].secret_id
            version = "latest"
          }
        }
      }

      env {
        name  = "LANGSMITH_PROJECT"
        value = var.langsmith_project
      }

      env {
        name  = "LANGSMITH_TRACING"
        value = tostring(var.langsmith_tracing_enabled)
      }

      env {
        name  = "LANGSMITH_ENDPOINT"
        value = var.langsmith_endpoint
      }

      # Frontend URL for OAuth callback (always created, empty string if not set)
      env {
        name  = "FRONTEND_URL"
        value = var.frontend_url
      }

      # Backend URL for OAuth callback (must match GitHub OAuth App registered callback)
      env {
        name  = "BACKEND_URL"
        value = var.backend_url
      }

      # External agent URLs (always created, empty string if not set)
      env {
        name  = "ORCHESTRATOR_URL"
        value = var.orchestrator_url
      }

      env {
        name  = "LOG_ATTACKER_URL"
        value = var.log_attacker_url
      }

      env {
        name  = "PATTERN_MINER_URL"
        value = var.pattern_miner_url
      }

      env {
        name  = "ACTION_AGENT_URL"
        value = var.action_agent_url
      }

      # Optional: External agent authentication tokens
      env {
        name = "ORCHESTRATOR_TOKEN"
        value_source {
          secret_key_ref {
            secret  = google_secret_manager_secret.orchestrator_token[0].secret_id
            version = "latest"
          }
        }
      }

      env {
        name = "PATTERN_MINER_TOKEN"
        value_source {
          secret_key_ref {
            secret  = google_secret_manager_secret.pattern_miner_token[0].secret_id
            version = "latest"
          }
        }
      }

      env {
        name = "ACTION_AGENT_TOKEN"
        value_source {
          secret_key_ref {
            secret  = google_secret_manager_secret.action_agent_token[0].secret_id
            version = "latest"
          }
        }
      }
    }

    service_account = data.google_compute_default_service_account.default.email
  }

  traffic {
    type    = "TRAFFIC_TARGET_ALLOCATION_TYPE_LATEST"
    percent = 100
  }

  lifecycle {
    ignore_changes = [template[0].vpc_access[0].connector]
  }
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

# Cloud Build GitHub Webhook Trigger
# Automatically triggers Docker build and Cloud Run deployment on git push to main
# NOTE: Requires GitHub App authentication setup in GCP Cloud Build console first
# See: https://cloud.google.com/build/docs/automating-builds/github/connect-repo-github
resource "google_cloudbuild_trigger" "dev_nexus_github" {
  count       = var.create_github_trigger ? 1 : 0
  name        = "pattern-discovery-agent-webhook"
  description = "Automatically build and deploy dev-nexus on GitHub push to main"
  filename    = "cloudbuild.yaml"
  disabled    = false

  github {
    owner = "DarojaAI"
    name  = "dev-nexus"
    push {
      branch = "^main$"
    }
  }

  substitutions = {
    _REGION              = var.region
    _ENVIRONMENT         = var.environment
    _KNOWLEDGE_BASE_REPO = var.knowledge_base_repo
    _FRONTEND_URL        = var.frontend_url
  }

  depends_on = [
    google_project_service.cloudbuild
  ]
}

# Data sources
data "google_project" "project" {
  project_id = var.project_id
}

data "google_compute_default_service_account" "default" {}

# Data source to read secret version for trigger
# This triggers Cloud Run redeploy when secret version changes
data "google_secret_manager_secret_version" "postgres_host" {
  secret = google_secret_manager_secret.postgres_host.id
}
