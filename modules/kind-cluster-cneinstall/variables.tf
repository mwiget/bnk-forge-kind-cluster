variable "kubeconfig" {
  description = "Base64-encoded kubeconfig for the kind cluster. Wired from kind-cluster-create / kind-cluster-register."
  type        = string
  sensitive   = true
  default     = ""
}

variable "flo_namespace" {
  description = "Namespace where FLO runs and where the CNEInstance is applied."
  type        = string
  default     = "f5-operators"
}

variable "flo_cluster_issuer_name" {
  description = "ClusterIssuer name FLO is bound to. Wired from the FLO module so CNEInstance.spec.certificate.clusterIssuer matches."
  type        = string
  default     = "bnk-ca-cluster-issuer"
}

variable "cneinstance_name" {
  description = "metadata.name for the CNEInstance CR."
  type        = string
  default     = "bnkgatewayclass-sample"
}

variable "manifest_version" {
  description = "spec.manifestVersion for the CNEInstance. Pin matches the f5-bnk-udf v2.2 lab default; bump for newer BNK releases."
  type        = string
  default     = "2.2.0-3.2226.0-0.0.385"
}

variable "deployment_size" {
  description = "spec.deploymentSize. 'Small' is right for kind/POC."
  type        = string
  default     = "Small"
}

variable "registry_uri" {
  description = "spec.registry.uri."
  type        = string
  default     = "repo.f5.com"
}

variable "image_pull_secret" {
  description = "Image pull secret name referenced by spec.registry. Created by the FLO module as 'far-secret'."
  type        = string
  default     = "far-secret"
}

variable "gateway_api" {
  description = "spec.product.gatewayAPI."
  type        = bool
  default     = true
}

variable "whole_cluster" {
  description = "spec.wholeCluster."
  type        = bool
  default     = true
}

variable "logging_enabled" {
  description = "spec.telemetry.loggingSubsystem.enabled."
  type        = bool
  default     = false
}

variable "metric_enabled" {
  description = "spec.telemetry.metricSubsystem.enabled."
  type        = bool
  default     = true
}

variable "demo_mode" {
  description = "spec.advanced.demoMode.enabled."
  type        = bool
  default     = true
}

variable "pseudo_cni_enabled" {
  description = "spec.pseudoCNI.enabled. False for kind without lab-networks."
  type        = bool
  default     = false
}

variable "dynamic_routing_enabled" {
  description = "spec.dynamicRouting.enabled. False for kind without lab-networks."
  type        = bool
  default     = false
}

variable "firewall_acl_enabled" {
  description = "spec.firewallACL.enabled."
  type        = bool
  default     = true
}

variable "core_collection_enabled" {
  description = "spec.coreCollection.enabled."
  type        = bool
  default     = false
}

variable "network_attachments" {
  description = "spec.networkAttachments. Empty list for kind without lab-networks; populate when running a full BNK data-plane lab."
  type        = list(string)
  default     = []
}
