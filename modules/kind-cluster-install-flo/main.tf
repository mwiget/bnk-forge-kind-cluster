locals {
  kc_raw = var.kubeconfig != "" ? base64decode(var.kubeconfig) : ""
  kc     = local.kc_raw != "" ? yamldecode(local.kc_raw) : null
}

provider "kubernetes" {
  host                   = try(local.kc.clusters[0].cluster.server, "")
  cluster_ca_certificate = try(base64decode(local.kc.clusters[0].cluster["certificate-authority-data"]), null)
  client_certificate     = try(base64decode(local.kc.users[0].user["client-certificate-data"]), null)
  client_key             = try(base64decode(local.kc.users[0].user["client-key-data"]), null)
}

provider "helm" {
  kubernetes = {
    host                   = try(local.kc.clusters[0].cluster.server, "")
    cluster_ca_certificate = try(base64decode(local.kc.clusters[0].cluster["certificate-authority-data"]), null)
    client_certificate     = try(base64decode(local.kc.users[0].user["client-certificate-data"]), null)
    client_key             = try(base64decode(local.kc.users[0].user["client-key-data"]), null)
  }
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

  # Suppress the data block in plan output — yaml_body otherwise emits the
  # base64-encoded auth blob in the diff.
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

resource "helm_release" "flo" {
  name       = "flo"
  repository = ""
  chart      = var.flo_chart_ref
  version    = var.flo_chart_version
  namespace  = var.flo_namespace
  wait       = var.wait_for_deployment
  timeout    = var.timeout

  # OCI registry auth for repo.f5.com is handled globally — the
  # cluster-create module runs `helm registry login` once using the same
  # FAR auth key, and the credential is persisted in
  # /home/bnkforge/.config/helm/registry/config.json (a persistent
  # docker-compose volume). The helm provider's OCI chart pull picks it
  # up at plan time. helm_release.repository_username/_password are HTTP-
  # only and silently ignored for OCI registries.

  # See cert-manager module — helm replace = true makes retries idempotent
  # when a prior apply errored after the helm install but before tofu state
  # was committed.
  replace = true

  values = [
    yamlencode({
      global = {
        imagePullSecrets = [{ name = "far-secret" }]
        certmgr = {
          clusterIssuer = var.cluster_issuer_name
        }
      }
      rbac = {
        create = true
      }
      containerPlatform     = var.container_platform
      ServiceIPFamily       = var.service_ip_family
      sharedComponentNamespace = ""
      namespace             = var.flo_namespace
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
  ]

  depends_on = [
    kubectl_manifest.far_secret_flo,
    kubectl_manifest.far_secret_default,
  ]
}
