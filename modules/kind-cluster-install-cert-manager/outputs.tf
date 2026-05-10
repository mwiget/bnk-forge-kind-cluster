output "namespace" {
  description = "Namespace where cert-manager is deployed."
  value       = var.namespace
  depends_on  = [kubectl_manifest.cert_manager_namespace]
}

output "helm_release_name" {
  description = "Name of the cert-manager Helm release."
  value       = helm_release.cert_manager.name
}

output "helm_release_version" {
  description = "Installed cert-manager Helm chart version."
  value       = helm_release.cert_manager.version
}

output "crd_ready" {
  description = "True once cert-manager CRDs are expected to be registered."
  value       = true
  depends_on  = [time_sleep.cert_manager_ready]
}

output "cluster_issuer_name" {
  description = "Name of the BNK CA ClusterIssuer downstream BNK modules consume."
  value       = var.cluster_issuer_name
}

output "selfsigned_cluster_issuer_name" {
  description = "Name of the bootstrap self-signed ClusterIssuer."
  value       = var.selfsigned_cluster_issuer_name
}
