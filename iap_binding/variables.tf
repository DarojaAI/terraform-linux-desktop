variable "project" {
  type        = string
  description = "GCP project ID"
}

variable "region" {
  type        = string
  description = "GCP region (optional)"
  default     = "us-central1"
}

variable "role" {
  type        = string
  description = "IAM role to bind (e.g. roles/iap.tunnelInstances.accessViaIAP)"
}

variable "members" {
  type        = list(string)
  description = "List of members to bind (e.g. user:you@example.com)"
}

variable "condition_enable" {
  type        = bool
  description = "Whether to enable an IAM condition on the binding"
  default     = false
}

variable "condition_title" {
  type        = string
  description = "Condition title"
  default     = ""
}

variable "condition_description" {
  type        = string
  description = "Condition description"
  default     = ""
}

variable "condition_expression" {
  type        = string
  description = "Condition expression for conditional binding"
  default     = ""
}
