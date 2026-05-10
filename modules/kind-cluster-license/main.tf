locals {
  kc_raw = var.kubeconfig != "" ? base64decode(var.kubeconfig) : ""
  kc     = local.kc_raw != "" ? yamldecode(local.kc_raw) : null
}

# alekc/kubectl provider — defers manifest application to apply time so
# the License CR doesn't fail plan-time CRD validation. The License CRD
# is registered by FLO's reconcile of the CNEInstance, not by the FLO
# helm chart directly — see terraform_data.wait_for_license_crd below.
provider "kubectl" {
  host                   = try(local.kc.clusters[0].cluster.server, "")
  cluster_ca_certificate = try(base64decode(local.kc.clusters[0].cluster["certificate-authority-data"]), "")
  client_certificate     = try(base64decode(local.kc.users[0].user["client-certificate-data"]), "")
  client_key             = try(base64decode(local.kc.users[0].user["client-key-data"]), "")
  load_config_file       = false
}

# Wait for the License CRD to be Established. The cneinstall module
# reports applied when the CNEInstance CR is created, but FLO's
# reconciliation (which deploys the BNK platform components and registers
# their CRDs, including licenses.k8s.f5net.com) takes additional time.
#
# `kubectl wait` errors immediately if the CRD doesn't exist yet (NotFound),
# so we poll for existence first, then wait for Established. Total budget
# 10 minutes — typical FLO reconcile on kind is 2-5 min depending on
# image pull speed.
resource "terraform_data" "wait_for_license_crd" {
  triggers_replace = {
    kc_hash = var.kubeconfig != "" ? sha256(var.kubeconfig) : ""
    crd     = "licenses.k8s.f5net.com"
  }

  provisioner "local-exec" {
    when = create
    environment = {
      KUBECONFIG_B64 = var.kubeconfig
    }
    command = <<-EOT
      set -euo pipefail
      KC=$(mktemp)
      trap 'rm -f "$KC"' EXIT
      printf '%s' "$KUBECONFIG_B64" | base64 -d > "$KC"

      echo "Polling for licenses.k8s.f5net.com CRD (FLO reconciles CNEInstance to register it)..."
      for i in $(seq 1 60); do
        if kubectl --kubeconfig "$KC" get crd licenses.k8s.f5net.com >/dev/null 2>&1; then
          echo "CRD found after $((i*10))s, waiting for Established condition..."
          kubectl --kubeconfig "$KC" wait \
            --for=condition=Established \
            crd/licenses.k8s.f5net.com \
            --timeout=120s
          exit 0
        fi
        echo "  attempt $i/60: CRD not yet registered, sleeping 10s..."
        sleep 10
      done

      echo "ERROR: licenses.k8s.f5net.com CRD did not appear within 600s." >&2
      echo "  Check FLO operator status:" >&2
      echo "    kubectl --kubeconfig <kc> -n ${var.license_namespace} get pods" >&2
      echo "    kubectl --kubeconfig <kc> get cneinstance -A -o yaml" >&2
      echo "    kubectl --kubeconfig <kc> -n ${var.license_namespace} logs -l app.kubernetes.io/name=f5-lifecycle-operator" >&2
      exit 1
    EOT
  }
}

# License CR — kubectl_manifest with apply semantics, idempotent across
# project recreates. apiVersion matches the bnk-forge-ibm-roks-cluster
# reference (k8s.f5net.com/v1, NOT k8s.f5.com/v1 which is the FLO
# operator's own group). spec.jwt is inlined per the ROKS pattern; the
# CRD doesn't accept a jwtSecretRef field.
resource "kubectl_manifest" "license" {
  yaml_body = yamlencode({
    apiVersion = "k8s.f5net.com/v1"
    kind       = "License"
    metadata = {
      name      = var.license_name
      namespace = var.license_namespace
    }
    spec = {
      operationMode = var.license_mode
      jwt           = var.jwt_token
    }
  })

  # Plan-output redaction is handled at the variable level — var.jwt_token
  # is sensitive=true in variables.tf, and that propagates through
  # yamlencode automatically.

  depends_on = [terraform_data.wait_for_license_crd]
}
