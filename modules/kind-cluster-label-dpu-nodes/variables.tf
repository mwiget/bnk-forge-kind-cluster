variable "kubeconfig" {
  description = "Base64-encoded kubeconfig for the kind cluster. Wired from kind-cluster-create / kind-cluster-register."
  type        = string
  sensitive   = true
  default     = ""
}

variable "dpu_node_names" {
  description = "Names of the kind worker nodes to mark as DPU-equivalent. Defaults to the f5-bnk-udf convention: workers 2 and 3."
  type        = list(string)
  default     = ["bnk-worker2", "bnk-worker3"]
}

variable "tmm_label_key" {
  description = "Label key applied to DPU nodes for TMM scheduling."
  type        = string
  default     = "app"
}

variable "tmm_label_value" {
  description = "Label value applied to DPU nodes for TMM scheduling."
  type        = string
  default     = "f5-tmm"
}

variable "dpu_taint_key" {
  description = "Taint key applied to DPU nodes."
  type        = string
  default     = "dpu"
}

variable "dpu_taint_value" {
  description = "Taint value applied to DPU nodes."
  type        = string
  default     = "true"
}

variable "dpu_taint_effect" {
  description = "Taint effect applied to DPU nodes."
  type        = string
  default     = "NoSchedule"
}
