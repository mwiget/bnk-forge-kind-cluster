resource "local_file" "kubeconfig" {
  filename        = "${path.module}/.kubeconfig"
  content         = base64decode(var.kubeconfig)
  file_permission = "0600"
}

provider "kubernetes" {
  config_path = local_file.kubeconfig.filename
}

provider "helm" {
  kubernetes = {
    config_path = local_file.kubeconfig.filename
  }
}

resource "kubernetes_namespace_v1" "flo" {
  metadata {
    name = var.flo_namespace
  }
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
}

resource "kubernetes_secret_v1" "far_secret_flo" {
  metadata {
    name      = "far-secret"
    namespace = kubernetes_namespace_v1.flo.metadata[0].name
  }
  type = "kubernetes.io/dockerconfigjson"
  data = {
    ".dockerconfigjson" = local.dockerconfigjson
  }
}

# Default-namespace copy used by CNEInstance image pulls (matches UDF behavior).
resource "kubernetes_secret_v1" "far_secret_default" {
  metadata {
    name      = "far-secret"
    namespace = "default"
  }
  type = "kubernetes.io/dockerconfigjson"
  data = {
    ".dockerconfigjson" = local.dockerconfigjson
  }
}

resource "helm_release" "flo" {
  name       = "flo"
  repository = ""
  chart      = var.flo_chart_ref
  version    = var.flo_chart_version
  namespace  = kubernetes_namespace_v1.flo.metadata[0].name
  wait       = var.wait_for_deployment
  timeout    = var.timeout

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
    kubernetes_secret_v1.far_secret_flo,
    kubernetes_secret_v1.far_secret_default,
  ]
}
