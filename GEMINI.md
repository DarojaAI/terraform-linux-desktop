# Project: dev-nexus Infrastructure

## Project Overview

This project contains the complete infrastructure-as-code to deploy and manage the "dev-nexus" application on Google Cloud Platform (GCP). It uses Terraform to provision and configure all the necessary resources, ensuring a repeatable and consistent deployment process.

The "dev-nexus" application appears to be a pattern discovery and analysis tool. It leverages a PostgreSQL database with the `pgvector` extension, which strongly suggests it works with vector embeddings for tasks like similarity search, likely on code or documentation patterns.

The core components of the infrastructure are:

*   **Google Cloud Run:** The application itself is deployed as a containerized service on Cloud Run, providing a serverless, scalable, and managed environment.
*   **Google Compute Engine (GCE):** A GCE VM is used to host the PostgreSQL database. This provides more control over the database environment, including the installation of custom extensions like `pgvector`.
*   **Google Secret Manager:** Used to securely store and manage sensitive information like API keys and database passwords.
*   **Google Cloud Storage (GCS):** A GCS bucket is used for storing backups of the PostgreSQL database.
*   **VPC and Firewall Rules:** A dedicated Virtual Private Cloud (VPC) is created to provide a secure and isolated network for the application and database.

## Building and Running

The project is managed entirely through Terraform. The following commands are used to manage the infrastructure lifecycle:

1.  **Initialization:**
    *   `terraform init`
    *   This command initializes the Terraform workspace, downloading the necessary providers and setting up the backend.

2.  **Planning:**
    *   `terraform plan`
    *   This command creates an execution plan, showing the changes that will be made to the infrastructure. It's a dry run that allows you to review the changes before applying them.

3.  **Applying:**
    *   `terraform apply`
    *   This command applies the changes to the infrastructure, creating, updating, or deleting resources as needed.

4.  **Destroying:**
    *   `terraform destroy`
    *   This command destroys all the resources managed by the Terraform configuration.

A `terraform.tfvars.example` file is provided to illustrate the required variables. You should copy this to `terraform.tfvars` and fill in your specific values.

## Development Conventions

*   **Infrastructure as Code:** All infrastructure is defined in `.tf` files, following Terraform best practices.
*   **Variable-driven Configuration:** The configuration is highly customizable through variables defined in `variables.tf`. This allows for easy configuration of different environments (e.g., development, staging, production).
*   **State Management:** The `README.md` recommends using a GCS bucket for remote state management, which is a best practice for collaborative projects.
*   **Database Initialization:** The database schema and initial setup are managed through a shell script (`postgres_init.sh`) that is executed on the GCE instance at startup. This ensures that the database is always in a known state.
*   **Security:** The project uses Secret Manager for secrets and has options for both public and private access to the Cloud Run service. Firewall rules are in place to restrict access to the database.
