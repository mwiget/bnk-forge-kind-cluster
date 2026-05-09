# kind-cluster-register

Reference an existing kind cluster and emit the BNK registration outputs so
bnk-forge auto-registers it. Mirrors the role `roks-cluster-register` plays in
`bnk-forge-ibm-roks-cluster`, minus the IBM provider / VPC discovery.

The module shells out to `kind get kubeconfig --internal --name <cluster_name>`
inside the bnk-forge worker container via the `external` data source. As of
provider v0.9.x, `tehcyx/kind` doesn't expose a data-only lookup for an
existing cluster, so going through the `kind` CLI is the path of least
resistance.

## Inputs

| Name | Default | Notes |
| ---- | ------- | ----- |
| `cluster_name` | `bnk` | Must already exist on the target Docker daemon. |
| `ssh_user`, `ssh_host`, `docker_host` | `""` | Same `DOCKER_HOST` derivation as `kind-cluster-create`. |

## Outputs

Identical shape to `kind-cluster-create` so the two modules are
interchangeable from a blueprint's point of view: `cluster_id`,
`cluster_name`, `cluster_endpoint`, `region`, `kubeconfig` (base64,
sensitive).

## Runtime requirements

- `kind` CLI on `$PATH` in the worker container.
- `jq` on `$PATH` (already present in the bnk-forge worker image).
- A reachable Docker daemon with the named cluster present. Apply fails with a
  clear error if the cluster isn't found.

## Dependencies

None. Entry point for `bnk-on-kind-existing-cluster`.
