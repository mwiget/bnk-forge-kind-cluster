# kind-cluster-install-cert-manager

Installs cert-manager onto a kind cluster and creates the two-step BNK CA
ClusterIssuer chain BNK consumes:

1. **Self-signed bootstrap ClusterIssuer** (`selfsigned-cluster-issuer`).
2. **CA Certificate** (`bnk-ca` in `cert-manager`) signed by the bootstrap.
3. **BNK CA ClusterIssuer** (`bnk-ca-cluster-issuer`) reading from the CA Secret.

Mirrors `f5-bnk-udf/resources/cluster-issuer.yaml`. Differences from
`bnk-forge-ibm-roks-cluster/modules/roks-cluster-install-cert-manager`:

- Kubeconfig is piped from the upstream cluster module instead of being
  fetched live via the IBM provider — kind has no cloud-provider lookup.
- The cluster-issuer chain is created here instead of being deferred to FLO,
  so this module emits a single `cluster_issuer_name` output downstream
  modules can wire to without inspecting individual CR statuses.

## Inputs / Outputs

See the module manifest. The only required input is `kubeconfig` (wired from
upstream); everything else has sensible defaults.

## Dependencies

`kind-cluster-create` or `kind-cluster-register` for the kubeconfig.

The blueprint typically also runs `kind-cluster-label-dpu-nodes` before this
module, but cert-manager has no dependency on the labels — they're ordered for
the convenience of the user (label first so failures fail fast).
