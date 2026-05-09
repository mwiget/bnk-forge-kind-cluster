resource "local_file" "kubeconfig" {
  filename        = "${path.module}/.kubeconfig"
  content         = base64decode(var.kubeconfig)
  file_permission = "0600"
}

provider "kubernetes" {
  config_path = local_file.kubeconfig.filename
}

# CNEInstance CR. Shape mirrors f5-bnk-udf/resources/cne-instance.yaml minus
# the macvlan networkAttachments + dynamicRouting + pseudoCNI features that
# require the lab-networks module (out of scope for v1).
resource "kubernetes_manifest" "cneinstance" {
  manifest = {
    apiVersion = "k8s.f5.com/v1"
    kind       = "CNEInstance"
    metadata = {
      name      = var.cneinstance_name
      namespace = var.flo_namespace
      labels = {
        "app.kubernetes.io/name"       = "f5-lifecycle-operator"
        "app.kubernetes.io/managed-by" = "bnk-forge"
      }
    }
    spec = {
      product = {
        gatewayAPI = var.gateway_api
        type       = "BNK"
      }
      manifestVersion = var.manifest_version
      wholeCluster    = var.whole_cluster
      telemetry = {
        loggingSubsystem = { enabled = var.logging_enabled }
        metricSubsystem  = { enabled = var.metric_enabled }
      }
      certificate = {
        clusterIssuer = var.flo_cluster_issuer_name
      }
      deploymentSize = var.deployment_size
      registry = {
        uri               = var.registry_uri
        imagePullSecrets  = [{ name = var.image_pull_secret }]
        imagePullPolicy   = "Always"
      }
      networkAttachments = var.network_attachments

      pseudoCNI       = { enabled = var.pseudo_cni_enabled }
      dynamicRouting  = { enabled = var.dynamic_routing_enabled }
      coreCollection  = { enabled = var.core_collection_enabled }
      firewallACL     = { enabled = var.firewall_acl_enabled }

      advanced = {
        demoMode        = { enabled = var.demo_mode }
        maintenanceMode = { enabled = false }
        envDiscovery = {
          enabled            = false
          stopOnFail         = true
          runAfterSuccess    = true
        }
      }
    }
  }
}
