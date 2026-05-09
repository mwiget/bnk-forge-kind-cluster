locals {
  effective_docker_host = (
    var.docker_host != "" ? var.docker_host :
    (var.ssh_user != "" && var.ssh_host != "" ? "ssh://${var.ssh_user}@${var.ssh_host}" : "")
  )
}

# Shell out to the kind CLI to fetch the in-network kubeconfig of the named
# cluster. Same approach as kind-cluster-create's kubeconfig data source —
# the tehcyx/kind provider has no data-only lookup and hardcodes the
# loopback (non-internal) variant of the kubeconfig anyway.
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
}
