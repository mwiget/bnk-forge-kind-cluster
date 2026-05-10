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

# alekc/kubectl provider — defers manifest application to apply time so
# the License CR doesn't fail plan-time CRD validation. The License CRD
# is registered by the FLO helm release earlier in the chain.
provider "kubectl" {
  host                   = try(local.kc.clusters[0].cluster.server, "")
  cluster_ca_certificate = try(base64decode(local.kc.clusters[0].cluster["certificate-authority-data"]), "")
  client_certificate     = try(base64decode(local.kc.users[0].user["client-certificate-data"]), "")
  client_key             = try(base64decode(local.kc.users[0].user["client-key-data"]), "")
  load_config_file       = false
}

# License Secret — JWT material.
resource "kubernetes_secret_v1" "license_jwt" {
  metadata {
    name      = "${var.license_name}-jwt"
    namespace = var.license_namespace
  }
  type = "Opaque"
  data = {
    "jwt" = var.jwt_token
  }
}

# License CR — references the Secret rather than embedding the JWT inline.
resource "kubectl_manifest" "license" {
  yaml_body = yamlencode({
    apiVersion = "k8s.f5.com/v1"
    kind       = "License"
    metadata = {
      name      = var.license_name
      namespace = var.license_namespace
    }
    spec = {
      operationMode = var.license_mode
      jwtSecretRef = {
        name = kubernetes_secret_v1.license_jwt.metadata[0].name
        key  = "jwt"
      }
    }
  })

  depends_on = [kubernetes_secret_v1.license_jwt]
}
