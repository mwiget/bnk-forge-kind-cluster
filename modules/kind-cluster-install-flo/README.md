# kind-cluster-install-flo

Thin wrapper around the F5 Lifecycle Operator Helm chart, sized for kind /
POC use. ~80% smaller than the FLO module shipped with
`bnk-forge-ibm-roks-cluster` — no IBM IAM trusted profile, no IBM CIS
controller config, no IBM COS lookups, no NAD setup. The trade-off is that
this module is for kind / generic on-prem only; it does not target IBM
infrastructure.

What it actually does:

1. Creates the FLO namespace (`f5-operators` by default).
2. Materializes the FAR pull secret (`far-secret`) in both `f5-operators` and `default` from the `far_auth_key` project secret. Same `_json_key_base64:<auth>` shape `f5-bnk-udf/add-far-registry.sh` produces.
3. Installs the FLO chart from `oci://repo.f5.com/charts/f5-lifecycle-operator`, with values rendered to:
   - `containerPlatform: Generic` (correct for kind)
   - `global.imagePullSecrets[0].name: far-secret`
   - `global.certmgr.clusterIssuer: bnk-ca-cluster-issuer` (from the cert-manager module)
   - `license.jwt: <jwt_token>` from the project secret
   - `license.operationMode`, `license.friendlyName`, `license.logLevel`

The chart version pin (`v2.9.27-0.2.10`) matches `f5-bnk-udf/install-bnk.sh`.
Bump it when you bump the BNK target version.

## Project secrets

| Name | Used for |
| ---- | -------- |
| `far_auth_key` | Materialized into the `far-secret` Secret in `f5-operators` and `default`. Provide the *extracted* contents of `f5-far-auth-key.tgz` (base64-encoded JSON service account key), not the raw `.tgz` bytes. |
| `jwt_token` | Templated into FLO Helm values for license registration. |

## Outputs

`flo_namespace`, `flo_release_name`, `flo_release_version`,
`flo_cluster_issuer_name`. Downstream modules (`cneinstall`, `license`)
consume these to know where TMM / the License CR should land.

## Dependencies

- `kind-cluster-install-cert-manager` (BNK CA ClusterIssuer must exist).
- Implicitly, the cluster module + label-dpu-nodes — without DPU labels, FLO
  will install fine but TMM pods stay Pending.
