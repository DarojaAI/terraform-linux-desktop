# =============================================================================
# Linux Desktop - Hetzner Terraform Configuration
# =============================================================================
# Provisions a single VM on Hetzner and outputs its IP for deployment

provider "hcloud" {
  token = var.hcloud_token
}

# =============================================================================
# Variables
# =============================================================================

variable "hcloud_token" {
  description = "Hetzner API token"
  type        = string
  sensitive   = true
}

variable "hcx_access_key" {
  description = "HCX S3 access key for Terraform state storage"
  type        = string
  sensitive   = true
  default     = ""
}

variable "hcx_secret_key" {
  description = "HCX S3 secret key for Terraform state storage"
  type        = string
  sensitive   = true
  default     = ""
}

variable "server_name" {
  description = "Name of the server (must be unique)"
  type        = string
}

variable "server_type" {
  description = "Hetzner server type (e.g., cpx21, cpx41)"
  type        = string
  default     = "cpx41"
}

variable "location" {
  description = "Hetzner datacenter location (e.g., fsn1, nbg1)"
  type        = string
  default     = "fsn1"
}

variable "image" {
  description = "OS image to use"
  type        = string
  default     = "ubuntu-22.04"
}

variable "ssh_keys" {
  description = "SSH key IDs or names to attach"
  type        = list(string)
  default     = []
}

variable "hetzner_ssh_key_name" {
  description = "Name of SSH key in Hetzner"
  type        = string
  default     = ""
}

variable "ssh_public_key" {
  description = "SSH public key to inject at boot (for passwordless access)"
  type        = string
  default     = ""
}

variable "labels" {
  description = "Labels to apply to resources"
  type        = map(string)
  default = {
    project    = "linux-desktop-seed"
    managed_by = "terraform"
  }
}

# =============================================================================
# Server
# =============================================================================

resource "hcloud_server" "main" {
  name        = var.server_name
  server_type = var.server_type
  location    = var.location
  image       = var.image

  # SSH keys - use directly, not dynamic block
  ssh_keys = var.hetzner_ssh_key_name != "" ? [var.hetzner_ssh_key_name] : var.ssh_keys

  labels = var.labels
}

# Server created - deployment script will handle further setup

# =============================================================================
# Outputs
# =============================================================================

output "server_id" {
  description = "Hetzner server ID"
  value       = hcloud_server.main.id
}

output "server_name" {
  description = "Server name"
  value       = hcloud_server.main.name
}

output "ipv4_address" {
  description = "Public IPv4 address"
  value       = hcloud_server.main.ipv4_address
}

output "ipv6_address" {
  description = "Public IPv6 address"
  value       = hcloud_server.main.ipv6_address
}

output "connection_info" {
  description = "Connection information for deployment"
  value       = "ssh -o StrictHostKeyChecking=no root@${hcloud_server.main.ipv4_address}"
  sensitive   = true
}