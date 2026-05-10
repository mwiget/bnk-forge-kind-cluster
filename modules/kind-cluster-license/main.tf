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

locals {
  license_secret_name = "${var.license_name}-jwt"
  jwt_token_b64       = base64encode(var.jwt_token)
}

# License Secret — JWT material. kubectl_manifest (apply semantics) so the
# secret tolerates an existing copy from a prior project on a shared kind
# cluster instead of erroring on AlreadyExists.
resource "kubectl_manifest" "license_jwt" {
  yaml_body = yamlencode({
    apiVersion = "v1"
    kind       = "Secret"
    type       = "Opaque"
    metadata = {
      name      = local.license_secret_name
      namespace = var.license_namespace
    }
    data = {
      jwt = local.jwt_token_b64
    }
  })

  # Plan-output redaction is handled at the variable level — var.jwt_token
  # is sensitive=true in variables.tf, and that propagates through
  # base64encode and yamlencode automatically.
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
        name = local.license_secret_name
        key  = "jwt"
      }
    }
  })

  depends_on = [kubectl_manifest.license_jwt]
}
