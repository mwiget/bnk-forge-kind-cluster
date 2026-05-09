resource "local_file" "kubeconfig" {
  filename        = "${path.module}/.kubeconfig"
  content         = base64decode(var.kubeconfig)
  file_permission = "0600"
}

provider "kubernetes" {
  config_path = local_file.kubeconfig.filename
}

provider "helm" {
  # Helm provider v3+ requires `kubernetes = {...}` (argument with equals),
  # not the legacy v2 `kubernetes {...}` block syntax.
  kubernetes = {
    config_path = local_file.kubeconfig.filename
  }
}

resource "kubernetes_namespace_v1" "cert_manager" {
  metadata {
    name = var.namespace
  }
}

resource "helm_release" "cert_manager" {
  name       = "cert-manager"
  repository = var.chart_repository
  chart      = "cert-manager"
  namespace  = kubernetes_namespace_v1.cert_manager.metadata[0].name
  version    = var.chart_version
  wait       = var.wait_for_deployment
  timeout    = var.timeout

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

  depends_on = [kubernetes_namespace_v1.cert_manager]
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
resource "kubernetes_manifest" "selfsigned_cluster_issuer" {
  manifest = {
    apiVersion = "cert-manager.io/v1"
    kind       = "ClusterIssuer"
    metadata   = { name = var.selfsigned_cluster_issuer_name }
    spec       = { selfSigned = {} }
  }
  depends_on = [time_sleep.cert_manager_ready]
}

resource "kubernetes_manifest" "bnk_ca_certificate" {
  manifest = {
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
  }
  depends_on = [kubernetes_manifest.selfsigned_cluster_issuer]
}

resource "kubernetes_manifest" "bnk_ca_cluster_issuer" {
  manifest = {
    apiVersion = "cert-manager.io/v1"
    kind       = "ClusterIssuer"
    metadata   = { name = var.cluster_issuer_name }
    spec = {
      ca = {
        secretName = var.ca_secret_name
      }
    }
  }
  depends_on = [kubernetes_manifest.bnk_ca_certificate]
}
