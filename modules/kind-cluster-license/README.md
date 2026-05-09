# kind-cluster-license

Applies the BNK `License` CR to a kind cluster, sourcing the JWT from the
`jwt_token` project secret. No IBM Cloud Object Storage path — kind blueprint
is COS-free by design.

The JWT is materialized to a Secret first (`<license_name>-jwt`) and the
License CR references it via `spec.jwtSecretRef`, instead of inlining the JWT
in the CR. Tighter blast radius if the CR ever leaks via `kubectl describe`.

## Project secrets

| Name | Used for |
| ---- | -------- |
| `jwt_token` | License JWT, written to a Secret in the FLO namespace. |

## Dependencies

`kind-cluster-cneinstall` (License is only meaningful after CNEInstance is up).
