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
# the CNEInstance CR doesn't fail plan-time CRD validation. The
# CNEInstance CRD is registered by the FLO helm release in the upstream
# `flo` module, which has applied by the time auto-wire feeds kubeconfig
# here, but plan-time validation runs before auto-wire fires.
provider "kubectl" {
  host                   = try(local.kc.clusters[0].cluster.server, "")
  cluster_ca_certificate = try(base64decode(local.kc.clusters[0].cluster["certificate-authority-data"]), "")
  client_certificate     = try(base64decode(local.kc.users[0].user["client-certificate-data"]), "")
  client_key             = try(base64decode(local.kc.users[0].user["client-key-data"]), "")
  load_config_file       = false
}

# CNEInstance CR. Shape mirrors f5-bnk-udf/resources/cne-instance.yaml minus
# the macvlan networkAttachments + dynamicRouting + pseudoCNI features that
# require the lab-networks module (out of scope for v1).
resource "kubectl_manifest" "cneinstance" {
  yaml_body = yamlencode({
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
  })
}
