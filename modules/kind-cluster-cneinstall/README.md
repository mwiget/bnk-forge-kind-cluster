# kind-cluster-cneinstall

Applies a `CNEInstance` CR to a kind cluster. Shape mirrors
`f5-bnk-udf/resources/cne-instance.yaml`, minus the features that need
lab-networks (macvlan `networkAttachments`, `pseudoCNI`, `dynamicRouting`).

## Defaults vs UDF

| Field | UDF (lab) | This module (kind/POC) |
| ----- | --------- | ---------------------- |
| `networkAttachments` | `[external-net, egress-net]` | `[]` |
| `pseudoCNI.enabled` | `true` | `false` |
| `dynamicRouting.enabled` | `true` | `false` |
| `firewallACL.enabled` | `true` | `true` |
| `advanced.demoMode.enabled` | `true` | `true` |
| `manifestVersion` | `2.2.0-3.2226.0-0.0.385` | same |

The disabled features can be flipped back on via inputs once a lab-networks
module is available.

## Dependencies

- `kind-cluster-install-flo` (FLO must be installed before the CNEInstance CRD is registered).
- Implicitly: cert-manager + label-dpu-nodes (otherwise TMM stays Pending after the CR applies).
