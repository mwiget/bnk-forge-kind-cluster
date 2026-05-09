output "cluster_id" {
  description = "Cluster ID for BNK registration. kind has no separate ID, so this aliases cluster_name."
  value       = var.cluster_name
}

output "cluster_name" {
  description = "Cluster name for BNK registration."
  value       = var.cluster_name
}

output "cluster_endpoint" {
  description = "Cluster API endpoint pulled from the in-network kubeconfig (https://<cluster_name>-control-plane:6443)."
  value       = data.external.kubeconfig.result.endpoint
}

output "region" {
  description = "Synthetic region label so the BNK Forge platform profile machinery has a value to compare. kind has no real region."
  value       = "local-kind"
}

output "docker_host" {
  description = "DOCKER_HOST value used for the kind invocation (empty when running against the local socket). Surfaced so downstream modules can compose the same value."
  value       = local.effective_docker_host
}

output "kubeconfig" {
  description = "Base64-encoded in-network kubeconfig for the cluster, fetched via `kind get kubeconfig --internal`. Server URL is the kind control-plane Docker DNS name so the bnk-forge worker container can reach the API server."
  value       = base64encode(data.external.kubeconfig.result.kubeconfig)
  sensitive   = true
}

output "kube_host" {
  description = "Cluster API host (same as cluster_endpoint)."
  value       = data.external.kubeconfig.result.endpoint
}
