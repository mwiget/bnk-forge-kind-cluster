variable "kubeconfig" {
  description = "Base64-encoded kubeconfig for the kind cluster."
  type        = string
  sensitive   = true
}

variable "far_auth_key" {
  description = "Contents of the F5 Artifacts Registry auth tarball (extracted JSON). Auto-injected by the bnk-forge variable assembler when a project secret of the same name exists."
  type        = string
  sensitive   = true
  default     = ""
}

variable "jwt_token" {
  description = "F5 BNK subscription JWT. Auto-injected by the bnk-forge variable assembler when a project secret of the same name exists."
  type        = string
  sensitive   = true
  default     = ""
}

variable "flo_namespace" {
  description = "Namespace for the F5 Lifecycle Operator and TMM workloads."
  type        = string
  default     = "f5-operators"
}

variable "cluster_issuer_name" {
  description = "Name of the BNK CA ClusterIssuer FLO and TMM components reference. Wired from the cert-manager module."
  type        = string
  default     = "bnk-ca-cluster-issuer"
}

variable "flo_chart_ref" {
  description = "OCI reference for the F5 Lifecycle Operator Helm chart."
  type        = string
  default     = "oci://repo.f5.com/charts/f5-lifecycle-operator"
}

variable "flo_chart_version" {
  description = "F5 Lifecycle Operator chart version."
  type        = string
  default     = "v2.9.27-0.2.10"
}

variable "container_platform" {
  description = "FLO containerPlatform value. 'Generic' is correct for kind."
  type        = string
  default     = "Generic"
}

variable "service_ip_family" {
  description = "FLO ServiceIPFamily value."
  type        = string
  default     = "ipv4"
}

variable "license_friendly_name" {
  description = "Friendly name advertised by FLO's license subsystem."
  type        = string
  default     = "BNK on kind"
}

variable "license_operation_mode" {
  description = "FLO license operation mode (connected or disconnected)."
  type        = string
  default     = "connected"

  validation {
    condition     = contains(["connected", "disconnected"], var.license_operation_mode)
    error_message = "license_operation_mode must be either 'connected' or 'disconnected'."
  }
}

variable "wait_for_deployment" {
  description = "Wait for FLO pods to become Ready."
  type        = bool
  default     = true
}

variable "timeout" {
  description = "Timeout (seconds) for the FLO Helm release."
  type        = number
  default     = 600
}
