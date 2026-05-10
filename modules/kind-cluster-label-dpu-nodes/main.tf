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

# Taints — applied via `kubectl taint --overwrite` instead of
# kubernetes_node_taint. The hashicorp/kubernetes provider has a known
# "Provider produced inconsistent result after apply" bug on
# kubernetes_node_taint with force=true: the controller normalizes the
# Node spec immediately after the apply, the read-back response omits the
# taint we just set, and the provider treats that as a state-mismatch
# error. kubectl --overwrite has none of those failure modes — it's
# idempotent across re-runs and tolerates the controller's concurrent
# edits to .spec.taints.
resource "terraform_data" "dpu_taints" {
  for_each = toset(var.dpu_node_names)

  triggers_replace = {
    node   = each.value
    key    = var.dpu_taint_key
    value  = var.dpu_taint_value
    effect = var.dpu_taint_effect
    # Bump when the auto-wired kubeconfig changes so taints get re-applied
    # against a freshly created cluster.
    kc_hash = var.kubeconfig != "" ? sha256(var.kubeconfig) : ""
  }

  # var.kubeconfig is already base64-encoded — safe to embed in the
  # heredoc since base64 contains only [A-Za-z0-9+/=]. Decode at apply
  # time into a tempfile that gets cleaned up by the trap.
  provisioner "local-exec" {
    when    = create
    command = <<-EOT
      set -euo pipefail
      KC=$(mktemp)
      trap 'rm -f "$KC"' EXIT
      echo '${var.kubeconfig}' | base64 -d > "$KC"
      kubectl --kubeconfig "$KC" taint node '${each.value}' \
        '${var.dpu_taint_key}=${var.dpu_taint_value}:${var.dpu_taint_effect}' \
        --overwrite
    EOT
  }

  # Destroy provisioners can't read variables, so untaint on destroy is a
  # no-op. The kind-cluster-create destroy provisioner deletes the whole
  # cluster, so leftover taints are moot. For the existing-cluster path,
  # downstream operators can untaint manually if needed.
}
