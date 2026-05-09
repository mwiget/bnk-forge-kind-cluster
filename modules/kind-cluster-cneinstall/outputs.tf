output "cneinstance_name" {
  description = "CNEInstance metadata.name."
  value       = var.cneinstance_name
}

output "cneinstance_namespace" {
  description = "CNEInstance metadata.namespace."
  value       = var.flo_namespace
}

output "manifest_version" {
  description = "spec.manifestVersion applied to the CNEInstance."
  value       = var.manifest_version
}
