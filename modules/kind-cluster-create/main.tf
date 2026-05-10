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
  exec_env = merge(
    local.effective_docker_host != "" ? { DOCKER_HOST = local.effective_docker_host } : {},
    { FAR_AUTH_KEY = var.far_auth_key },
  )

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

      # Attach the bnk-forge containers to the kind Docker network so the
      # celery worker can resolve <cluster_name>-control-plane via Docker
      # DNS — that's the server URL emitted by `kind get kubeconfig --internal`,
      # and downstream modules' kubernetes/helm providers need to reach it.
      # Without this attachment, every downstream apply fails with
      # "dial tcp: lookup <cluster_name>-control-plane on 127.0.0.11:53: no such host".
      ATTACHED=$(docker network inspect kind -f '{{range .Containers}}{{.Name}} {{end}}' 2>/dev/null || echo '')
      for C in bnk-forge-backend bnk-forge-celery-worker bnk-forge-celery-worker-2 bnk-forge-celery-beat; do
        if echo "$ATTACHED" | grep -qw "$C"; then
          echo "(skip) $C already attached to the kind network"
        elif docker ps --format '{{.Names}}' | grep -qx "$C"; then
          docker network connect kind "$C" && echo "connected $C to kind network" || echo "(warn) failed to connect $C"
        else
          echo "(skip) $C is not running"
        fi
      done

      # If the project supplies a FAR auth key, prime the helm registry
      # session so downstream helm_release blocks pulling oci://repo.f5.com/...
      # (FLO chart in particular) succeed at plan time. Helm OCI doesn't
      # support per-resource credentials in the helm provider; auth is
      # global state in /home/bnkforge/.config/helm/registry/config.json,
      # which IS a persistent docker-compose volume, so logging in once
      # here covers every subsequent module run.
      if [ -n "$FAR_AUTH_KEY" ]; then
        printf '%s' "$FAR_AUTH_KEY" | helm registry login -u _json_key_base64 --password-stdin repo.f5.com \
          && echo "logged into repo.f5.com via FAR auth key" \
          || echo "(warn) helm registry login to repo.f5.com failed — downstream FLO chart pull may fail"
      else
        echo "(skip) no FAR auth key supplied — helm registry login skipped"
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
