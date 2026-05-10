locals {
  # Parse the auto-wired kubeconfig at plan time so provider attributes
  # resolve without writing a file first.
  kc_raw = var.kubeconfig != "" ? base64decode(var.kubeconfig) : ""
  kc     = local.kc_raw != "" ? yamldecode(local.kc_raw) : null
}

provider "kubernetes" {
  host                   = try(local.kc.clusters[0].cluster.server, "")
  cluster_ca_certificate = try(base64decode(local.kc.clusters[0].cluster["certificate-authority-data"]), null)
  client_certificate     = try(base64decode(local.kc.users[0].user["client-certificate-data"]), null)
  client_key             = try(base64decode(local.kc.users[0].user["client-key-data"]), null)
}

# Apply labels — kubernetes_labels is upsert-style, idempotent across re-runs.
resource "kubernetes_labels" "dpu_nodes" {
  for_each    = toset(var.dpu_node_names)
  api_version = "v1"
  kind        = "Node"
  metadata {
    name = each.value
  }
  labels = {
    (var.tmm_label_key) = var.tmm_label_value
  }
}

# Taints — kubernetes_node_taint is similarly upsert-style.
# `force = true` because kube-controller-manager also manages
# .spec.taints (it adds NotReady/Unschedulable conditions during node
# lifecycle), and Terraform's server-side apply otherwise refuses to
# update the field with "Field manager conflict".
resource "kubernetes_node_taint" "dpu_nodes" {
  for_each = toset(var.dpu_node_names)
  metadata {
    name = each.value
  }
  taint {
    key    = var.dpu_taint_key
    value  = var.dpu_taint_value
    effect = var.dpu_taint_effect
  }
  force = true
}
