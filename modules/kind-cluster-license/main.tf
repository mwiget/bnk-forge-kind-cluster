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
resource "kubernetes_manifest" "license" {
  manifest = {
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
  }

  depends_on = [kubernetes_secret_v1.license_jwt]
}
