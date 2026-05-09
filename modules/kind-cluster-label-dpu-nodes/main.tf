locals {
  kubeconfig_decoded = base64decode(var.kubeconfig)
}

provider "kubernetes" {
  config_path = local_file.kubeconfig.filename
}

# Materialize the kubeconfig to a tmp file so the kubernetes provider can
# consume it via config_path. Inline kubeconfig support varies between
# provider versions; the file path is the lowest common denominator.
resource "local_file" "kubeconfig" {
  filename        = "${path.module}/.kubeconfig"
  content         = local.kubeconfig_decoded
  file_permission = "0600"
}

# Apply labels — kubernetes_labels is upsert-style, so this is idempotent and
# survives node re-creation by the kind provider.
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
  depends_on = [local_file.kubeconfig]
}

# Taints — kubernetes_node_taint is similarly upsert-style.
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
  depends_on = [local_file.kubeconfig]
}
