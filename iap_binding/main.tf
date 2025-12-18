terraform {
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = ">= 4.0"
    }
  }
}

provider "google" {
  project = var.project
  region  = var.region
}

resource "google_project_iam_binding" "iap_tunnel" {
  project = var.project
  role    = var.role
  members = var.members

  dynamic "condition" {
    for_each = var.condition_enable ? [1] : []
    content {
      title       = var.condition_title
      description = var.condition_description
      expression  = var.condition_expression
    }
  }
}
