module "iap_tunnel_example" {
  source = ".."

  project = "your-gcp-project"
  role    = "roles/iap.tunnelInstances.accessViaIAP"
  members = ["user:you@example.com"]

  condition_enable      = false
}
