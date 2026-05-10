variable "kubeconfig" {
  description = "Base64-encoded kubeconfig for the kind cluster. Wired from kind-cluster-create / kind-cluster-register."
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

variable "license_namespace" {
  description = "Namespace where the License CR is applied. Matches the FLO namespace by convention."
  type        = string
  default     = "f5-operators"
}

variable "license_name" {
  description = "metadata.name for the License CR."
  type        = string
  default     = "bnk-license"
}

variable "license_mode" {
  description = "spec.operationMode (connected | disconnected)."
  type        = string
  default     = "connected"

  validation {
    condition     = contains(["connected", "disconnected"], var.license_mode)
    error_message = "license_mode must be either 'connected' or 'disconnected'."
  }
}
