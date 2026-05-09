locals {
  # Prefer an explicit docker_host override; otherwise compose ssh://user@host
  # from the bare-metal credential template fields if both are populated;
  # otherwise leave empty and let the kind CLI use the local socket.
  effective_docker_host = (
    var.docker_host != "" ? var.docker_host :
    (var.ssh_user != "" && var.ssh_host != "" ? "ssh://${var.ssh_user}@${var.ssh_host}" : "")
  )

  # Empty environment when effective_docker_host is empty so kind picks up
  # /var/run/docker.sock; populated DOCKER_HOST otherwise. Per-resource
  # local-exec env, so per-deploy host selection works without bnk-forge core changes.
  exec_env = local.effective_docker_host != "" ? { DOCKER_HOST = local.effective_docker_host } : {}

  kind_config_path = abspath("${path.module}/payload/kind.yaml")
}

# Why terraform_data + local-exec instead of the tehcyx/kind provider:
#
# 1. The provider hardcodes the kind library's `internal` flag to false, so
#    kind_cluster.kubeconfig always emits the host-loopback variant
#    (https://127.0.0.1:<random-port>). bnk-forge's celery worker can't reach
#    that — it's outside the kind Docker network. We need `kind get kubeconfig
#    --internal` to emit an in-network kubeconfig (https://<name>-control-plane:6443).
#
# 2. The provider reads DOCKER_HOST from process env at provider-init time,
#    which only lets us target one Docker daemon per bnk-forge instance.
#    local-exec's `environment = {}` argument lets us inject DOCKER_HOST
#    per-resource — supports per-project remote-host selection without
#    coupling bnk-forge core to kind.
#
# Trade-off: lose declarative state for the cluster itself. Acceptable because
# this module already declares supports_drift = false and kind clusters are
# cheap to recreate.
resource "terraform_data" "cluster" {
  triggers_replace = {
    cluster_name = var.cluster_name
    docker_host  = local.effective_docker_host
    config_hash  = filemd5(local.kind_config_path)
  }

  provisioner "local-exec" {
    when    = create
    command = <<-EOT
      set -euo pipefail
      if kind get clusters 2>/dev/null | grep -qx '${var.cluster_name}'; then
        echo "kind cluster '${var.cluster_name}' already exists — skipping create"
      else
        kind create cluster \
          --name '${var.cluster_name}' \
          --config '${local.kind_config_path}' \
          ${var.kind_node_image != "" ? "--image '${var.kind_node_image}'" : ""}
      fi
    EOT

    environment = local.exec_env
  }

  # Destroy provisioners can only reference `self.*`, hence triggers_replace.
  provisioner "local-exec" {
    when    = destroy
    command = <<-EOT
      set -euo pipefail
      kind delete cluster --name '${self.triggers_replace["cluster_name"]}' || true
    EOT

    environment = self.triggers_replace["docker_host"] != "" ? {
      DOCKER_HOST = self.triggers_replace["docker_host"]
    } : {}
  }
}

# Pull the in-network kubeconfig + endpoint after the cluster exists.
# `data "external"` doesn't take an `environment = {}` arg, so DOCKER_HOST is
# exported inside the script. Values come via Terraform string interpolation,
# not the `query` channel — keeps the script self-contained.
data "external" "kubeconfig" {
  program = ["bash", "-c", <<-EOT
    set -euo pipefail
    if [ -n "${local.effective_docker_host}" ]; then
      export DOCKER_HOST="${local.effective_docker_host}"
    fi

    if ! kind get clusters 2>/dev/null | grep -qx '${var.cluster_name}'; then
      echo "kind cluster '${var.cluster_name}' not found on the target Docker daemon" >&2
      exit 1
    fi

    KC=$(kind get kubeconfig --internal --name '${var.cluster_name}')
    EP=$(echo "$KC" | awk '/server:/ {print $2; exit}')

    jq -nc \
      --arg kubeconfig "$KC" \
      --arg endpoint "$EP" \
      '{kubeconfig: $kubeconfig, endpoint: $endpoint}'
  EOT
  ]

  depends_on = [terraform_data.cluster]
}
