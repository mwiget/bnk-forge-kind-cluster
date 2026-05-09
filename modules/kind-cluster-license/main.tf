resource "local_file" "kubeconfig" {
  filename        = "${path.module}/.kubeconfig"
  content         = base64decode(var.kubeconfig)
  file_permission = "0600"
}

provider "kubernetes" {
  config_path = local_file.kubeconfig.filename
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
