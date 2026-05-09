output "flo_namespace" {
  description = "Namespace where FLO and TMM workloads run."
  value       = kubernetes_namespace_v1.flo.metadata[0].name
}

output "flo_release_name" {
  description = "Helm release name for FLO."
  value       = helm_release.flo.name
}

output "flo_release_version" {
  description = "Installed FLO chart version."
  value       = helm_release.flo.version
}

output "flo_cluster_issuer_name" {
  description = "ClusterIssuer FLO bound to. Pass-through of the input value, exposed so downstream modules can reference it without re-deriving."
  value       = var.cluster_issuer_name
}
