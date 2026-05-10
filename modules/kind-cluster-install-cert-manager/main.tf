locals {
  # Parse the auto-wired kubeconfig at plan time so provider attributes
  # resolve without writing a file first. local_file -> config_path doesn't
  # work for resources that validate server-side at plan time
  # (kubernetes_manifest in particular) — the provider stat()s config_path
  # before local_file gets a chance to write it.
  #
  # try() guards against the kubeconfig variable being empty during initial
  # plan (before auto-wire fires) — same shape as the IBM ROKS modules use
  # with data.ibm_container_cluster_config.
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
  # Helm provider v3+ requires `kubernetes = {...}` (argument with equals),
  # not the legacy v2 `kubernetes {...}` block syntax.
  kubernetes = {
    host                   = try(local.kc.clusters[0].cluster.server, "")
    cluster_ca_certificate = try(base64decode(local.kc.clusters[0].cluster["certificate-authority-data"]), null)
    client_certificate     = try(base64decode(local.kc.users[0].user["client-certificate-data"]), null)
    client_key             = try(base64decode(local.kc.users[0].user["client-key-data"]), null)
  }
}

# alekc/kubectl provider — defers manifest application entirely to apply
# time (no plan-time CRD validation). Required for the cert-manager
# ClusterIssuer/Certificate manifests below: their CRDs are registered by
# the helm_release in this same plan, and hashicorp/kubernetes's
# kubernetes_manifest would fail with "no matches for kind ClusterIssuer
# in group cert-manager.io" because plan-time validation runs before
# helm_release applies.
provider "kubectl" {
  host                   = try(local.kc.clusters[0].cluster.server, "")
  cluster_ca_certificate = try(base64decode(local.kc.clusters[0].cluster["certificate-authority-data"]), "")
  client_certificate     = try(base64decode(local.kc.users[0].user["client-certificate-data"]), "")
  client_key             = try(base64decode(local.kc.users[0].user["client-key-data"]), "")
  load_config_file       = false
}

# kubectl_manifest (apply semantics) so the namespace tolerates existing
# state — kubernetes_namespace_v1 errors with AlreadyExists when an old
# project's namespace persists on the cluster but the new project's tofu
# state is empty (common on kind where projects come and go but the
# cluster sticks around).
resource "kubectl_manifest" "cert_manager_namespace" {
  yaml_body = yamlencode({
    apiVersion = "v1"
    kind       = "Namespace"
    metadata   = { name = var.namespace }
  })
}

resource "helm_release" "cert_manager" {
  name       = "cert-manager"
  repository = var.chart_repository
  chart      = "cert-manager"
  namespace  = var.namespace
  version    = var.chart_version
  wait       = var.wait_for_deployment
  timeout    = var.timeout

  # If a previous failed apply left an orphan release in helm's history but
  # not in tofu state (e.g. kubectl_manifest step errored after helm
  # succeeded), recreate cleanly instead of "cannot re-use a name that is
  # still in use".
  replace = true

  set = [
    {
      name  = "installCRDs"
      value = "true"
    },
    {
      name  = "featureGates"
      value = "ServerSideApply=true"
    },
  ]

  depends_on = [kubectl_manifest.cert_manager_namespace]
}

# Wait briefly so cert-manager CRDs (ClusterIssuer, Certificate, …) are
# fully registered before downstream resources reference them.
resource "time_sleep" "cert_manager_ready" {
  depends_on      = [helm_release.cert_manager]
  create_duration = "${var.post_deployment_delay}s"
}

# The BNK CA chain. Mirrors f5-bnk-udf/resources/cluster-issuer.yaml — a
# bootstrap self-signed ClusterIssuer signs a CA Certificate, and a second
# ClusterIssuer (bnk-ca-cluster-issuer) consumes that Secret. Downstream BNK
# components (FLO, CNEInstance) reference bnk-ca-cluster-issuer.
#
# All three use kubectl_manifest (apply-time validation only) instead of
# kubernetes_manifest (plan-time validation) because the CRDs they depend
# on are registered by the cert-manager helm_release in this same plan.
resource "kubectl_manifest" "selfsigned_cluster_issuer" {
  yaml_body = yamlencode({
    apiVersion = "cert-manager.io/v1"
    kind       = "ClusterIssuer"
    metadata   = { name = var.selfsigned_cluster_issuer_name }
    spec       = { selfSigned = {} }
  })
  depends_on = [time_sleep.cert_manager_ready]
}

resource "kubectl_manifest" "bnk_ca_certificate" {
  yaml_body = yamlencode({
    apiVersion = "cert-manager.io/v1"
    kind       = "Certificate"
    metadata = {
      name      = var.ca_certificate_name
      namespace = var.namespace
    }
    spec = {
      isCA       = true
      commonName = var.ca_certificate_name
      secretName = var.ca_secret_name
      issuerRef = {
        name  = var.selfsigned_cluster_issuer_name
        kind  = "ClusterIssuer"
        group = "cert-manager.io"
      }
    }
  })
  depends_on = [kubectl_manifest.selfsigned_cluster_issuer]
}

resource "kubectl_manifest" "bnk_ca_cluster_issuer" {
  yaml_body = yamlencode({
    apiVersion = "cert-manager.io/v1"
    kind       = "ClusterIssuer"
    metadata   = { name = var.cluster_issuer_name }
    spec = {
      ca = {
        secretName = var.ca_secret_name
      }
    }
  })
  depends_on = [kubectl_manifest.bnk_ca_certificate]
}
