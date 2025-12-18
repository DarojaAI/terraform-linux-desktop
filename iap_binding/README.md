This Terraform module creates a project-level IAM binding for the IAP SSH tunnel role with an optional condition.

Usage example:

```hcl
module "iap_tunnel" {
  source = "./terraform/iap_binding"

  project = "your-gcp-project"
  role    = "roles/iap.tunnelInstances.accessViaIAP"
  members = ["user:you@example.com"]

  # If your organization requires conditional bindings, enable and set the condition
  condition_enable      = true
  condition_title       = "Allow IAP for specific users"
  condition_description = "Example condition"
  condition_expression  = "request.time < timestamp('2025-01-01T00:00:00Z')"
}
```

Note: Many organizations require IAM conditions for project-level bindings. If your project policy enforces conditions, set `condition_enable = true` and provide a valid `condition_expression`.
