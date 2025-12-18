output "binding_id" {
  description = "Resource ID of the IAM binding"
  value       = google_project_iam_binding.iap_tunnel.id
}
