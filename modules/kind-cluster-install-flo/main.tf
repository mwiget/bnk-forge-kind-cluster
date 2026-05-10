locals {
  kc_raw = var.kubeconfig != "" ? base64decode(var.kubeconfig) : ""
  kc     = local.kc_raw != "" ? yamldecode(local.kc_raw) : null
}

# alekc/kubectl provider — required for the kubectl_manifest namespace and
# secret resources below. Matches the cert-manager module's configuration.
provider "kubectl" {
  host                   = try(local.kc.clusters[0].cluster.server, "")
  cluster_ca_certificate = try(base64decode(local.kc.clusters[0].cluster["certificate-authority-data"]), "")
  client_certificate     = try(base64decode(local.kc.users[0].user["client-certificate-data"]), "")
  client_key             = try(base64decode(local.kc.users[0].user["client-key-data"]), "")
  load_config_file       = false
}

# kubectl_manifest (apply semantics) for the namespace and far secrets so
# they tolerate leftover resources from prior projects — kind clusters are
# long-lived but bnk-forge tofu state resets on every project, so without
# apply semantics every retry hits AlreadyExists.
resource "kubectl_manifest" "flo_namespace" {
  yaml_body = yamlencode({
    apiVersion = "v1"
    kind       = "Namespace"
    metadata   = { name = var.flo_namespace }
  })
}

# Materialize the FAR pull secret from the project secret. far_auth_key is
# the extracted (post-`tar zxOf`) contents of f5-far-auth-key.tgz — the
# base64-encoded JSON service account key. The dockerconfigjson auth field is
# then base64( "_json_key_base64:${far_auth_key}" ), matching the shape
# f5-bnk-udf/add-far-registry.sh produces.
locals {
  far_auth_b64 = base64encode("_json_key_base64:${var.far_auth_key}")

  dockerconfigjson = jsonencode({
    auths = {
      "repo.f5.com" = {
        auth = local.far_auth_b64
      }
    }
  })

  # Pre-encoded so the kubectl_manifest yaml_body matches kubernetes' wire
  # format for type=kubernetes.io/dockerconfigjson secrets.
  dockerconfigjson_b64 = base64encode(local.dockerconfigjson)
}

resource "kubectl_manifest" "far_secret_flo" {
  yaml_body = yamlencode({
    apiVersion = "v1"
    kind       = "Secret"
    type       = "kubernetes.io/dockerconfigjson"
    metadata = {
      name      = "far-secret"
      namespace = var.flo_namespace
    }
    data = {
      ".dockerconfigjson" = local.dockerconfigjson_b64
    }
  })

  # Plan-output redaction is handled at the variable level — var.far_auth_key
  # is sensitive=true in variables.tf, and that propagates through
  # base64encode and yamlencode automatically.

  depends_on = [kubectl_manifest.flo_namespace]
}

# Default-namespace copy used by CNEInstance image pulls (matches UDF behavior).
resource "kubectl_manifest" "far_secret_default" {
  yaml_body = yamlencode({
    apiVersion = "v1"
    kind       = "Secret"
    type       = "kubernetes.io/dockerconfigjson"
    metadata = {
      name      = "far-secret"
      namespace = "default"
    }
    data = {
      ".dockerconfigjson" = local.dockerconfigjson_b64
    }
  })
}

locals {
  flo_values_yaml = yamlencode({
    global = {
      imagePullSecrets = [{ name = "far-secret" }]
      certmgr = {
        clusterIssuer = var.cluster_issuer_name
      }
    }
    rbac = {
      create = true
    }
    containerPlatform        = var.container_platform
    ServiceIPFamily          = var.service_ip_family
    sharedComponentNamespace = ""
    namespace                = var.flo_namespace
    image = {
      repository = "repo.f5.com/images"
      name       = "f5-lifecycle-operator"
      pullPolicy = "Always"
    }
    fluentbit_sidecar = {
      enabled = true
      image = {
        name = "f5-fluentbit"
      }
    }
    license = {
      operationMode = var.license_operation_mode
      logLevel      = "info"
      jwt           = var.jwt_token
      friendlyName  = var.license_friendly_name
    }
  })

  flo_wait_arg = var.wait_for_deployment ? "--wait" : ""
}

# Drive the FLO helm install via the helm CLI directly rather than the
# hashicorp/helm provider. Reasons:
#
# 1. The provider's OCI auth doesn't share state with `helm registry
#    login`. Even after `data "external"` runs the login (and the
#    credential is correctly written to ~/.config/helm/registry/config.json
#    on the worker), the provider's plan-time chart fetch still 403's —
#    it ships its own helm Go SDK with auth handling that doesn't pick
#    up the on-disk config. Verified empirically: `helm pull oci://...`
#    succeeds from the same worker, but `helm_release` fails.
#
# 2. helm CLI in this image (3.20) supports `helm upgrade --install`,
#    which is intrinsically idempotent against existing releases —
#    drops the need for a separate pre-uninstall step too.
#
# 3. Plan-time chart manifest fetch is bypassed entirely; auth happens
#    inside the apply-time script, just before the install.
resource "terraform_data" "flo_helm_install" {
  triggers_replace = {
    chart_ref     = var.flo_chart_ref
    chart_version = var.flo_chart_version
    namespace     = var.flo_namespace
    values_hash   = sha256(local.flo_values_yaml)
    far_hash      = var.far_auth_key != "" ? sha256(var.far_auth_key) : ""
    kc_hash       = var.kubeconfig != "" ? sha256(var.kubeconfig) : ""
  }

  provisioner "local-exec" {
    when = create
    environment = {
      FAR_AUTH_KEY    = var.far_auth_key
      KUBECONFIG_B64  = var.kubeconfig
      VALUES_YAML     = local.flo_values_yaml
    }
    command = <<-EOT
      set -euo pipefail

      KC=$(mktemp)
      VALUES=$(mktemp)
      trap 'rm -f "$KC" "$VALUES"' EXIT

      printf '%s' "$KUBECONFIG_B64" | base64 -d > "$KC"
      printf '%s' "$VALUES_YAML"               > "$VALUES"

      if [ -n "$FAR_AUTH_KEY" ]; then
        printf '%s' "$FAR_AUTH_KEY" | helm registry login \
          -u _json_key_base64 --password-stdin repo.f5.com >&2
      fi

      # `upgrade --install` adopts an existing release if present and
      # creates one otherwise — fully idempotent, no AlreadyExists race.
      helm --kubeconfig "$KC" upgrade --install flo \
        '${var.flo_chart_ref}' \
        --version '${var.flo_chart_version}' \
        --namespace '${var.flo_namespace}' \
        --values "$VALUES" \
        ${local.flo_wait_arg} \
        --timeout '${var.timeout}s' >&2
    EOT
  }

  # Best-effort uninstall on destroy. self.triggers_replace carries the
  # state we need; var.* is unavailable in destroy provisioners.
  provisioner "local-exec" {
    when = destroy
    command = <<-EOT
      set -euo pipefail
      echo "(flo destroy provisioner cannot read kubeconfig — leaving release in cluster)" >&2
      true
    EOT
  }

  depends_on = [
    kubectl_manifest.far_secret_flo,
    kubectl_manifest.far_secret_default,
  ]
}
