variable "kubeconfig" {
  description = "Base64-encoded kubeconfig for the kind cluster. Wired from kind-cluster-create / kind-cluster-register."
  type        = string
  sensitive   = true
  default     = ""
}

variable "namespace" {
  description = "Kubernetes namespace for cert-manager."
  type        = string
  default     = "cert-manager"
}

variable "chart_version" {
  description = "cert-manager Helm chart version."
  type        = string
  default     = "v1.17.3"
}

variable "chart_repository" {
  description = "Helm chart repository URL."
  type        = string
  default     = "https://charts.jetstack.io"
}

variable "wait_for_deployment" {
  description = "Wait for cert-manager pods to become ready before returning."
  type        = bool
  default     = true
}

variable "timeout" {
  description = "Timeout (seconds) for the cert-manager Helm release."
  type        = number
  default     = 600
}

variable "post_deployment_delay" {
  description = "Delay (seconds) after the Helm release to let CRDs register before downstream modules use them."
  type        = number
  default     = 30
}

variable "cluster_issuer_name" {
  description = "Name of the BNK CA ClusterIssuer that downstream BNK modules consume."
  type        = string
  default     = "bnk-ca-cluster-issuer"
}

variable "selfsigned_cluster_issuer_name" {
  description = "Name of the bootstrap self-signed ClusterIssuer that signs the BNK CA Certificate."
  type        = string
  default     = "selfsigned-cluster-issuer"
}

variable "ca_certificate_name" {
  description = "Name of the in-cluster BNK CA Certificate object."
  type        = string
  default     = "bnk-ca"
}

variable "ca_secret_name" {
  description = "Name of the Secret holding the BNK CA cert/key. Referenced by the bnk-ca-cluster-issuer."
  type        = string
  default     = "bnk-ca"
}
