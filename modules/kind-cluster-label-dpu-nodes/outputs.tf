output "labeled_nodes" {
  description = "List of node names that received the TMM label and DPU taint."
  value       = var.dpu_node_names
}

output "tmm_label" {
  description = "Label applied to DPU nodes (key=value form for downstream selectors)."
  value       = "${var.tmm_label_key}=${var.tmm_label_value}"
}

output "dpu_taint" {
  description = "Taint applied to DPU nodes (key=value:effect form)."
  value       = "${var.dpu_taint_key}=${var.dpu_taint_value}:${var.dpu_taint_effect}"
}
