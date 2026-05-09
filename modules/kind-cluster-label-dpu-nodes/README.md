# kind-cluster-label-dpu-nodes

kind clusters don't have real DPUs, so FLO/TMM pod scheduling needs help.
This module labels two worker nodes `app=f5-tmm` and taints them
`dpu=true:NoSchedule`, which is the convention `f5-bnk-udf/install-bnk.sh`
uses for the same emulation.

Required for the BNK install chain on kind. Skip it and FLO will install
fine but TMM pods will sit Pending.

## Inputs

| Name | Default | Notes |
| ---- | ------- | ----- |
| `kubeconfig` | _module input_ | Base64 kubeconfig from upstream cluster module. |
| `dpu_node_names` | `["bnk-worker2", "bnk-worker3"]` | Defaults match the vendored `kind.yaml`'s 4-worker topology. |
| `tmm_label_key`, `tmm_label_value` | `app`, `f5-tmm` | TMM scheduling key. |
| `dpu_taint_{key,value,effect}` | `dpu`, `true`, `NoSchedule` | Taint applied. |

## Outputs

| Name | Notes |
| ---- | ----- |
| `labeled_nodes` | Echo of `dpu_node_names`. |
| `tmm_label` | `key=value` form for downstream selector wiring. |
| `dpu_taint` | `key=value:effect` form. |

## Dependencies

`kind-cluster-create` (or `kind-cluster-register`) must run first so the
kubeconfig output is available.
