# kind-cluster-create

Provisions a [kind](https://kind.sigs.k8s.io/) cluster suitable for running BNK
in a developer / POC setting.

## Why we don't use the `tehcyx/kind` Terraform provider

Two reasons:

1. **The provider only emits the host-loopback kubeconfig.** It hardcodes the kind library's `internal` flag to `false`, so `kind_cluster.kubeconfig` always returns `https://127.0.0.1:<random-port>` — unreachable from the bnk-forge celery worker, which sits outside the kind Docker network. We need `kind get kubeconfig --internal` to produce a kubeconfig with the in-network `https://<name>-control-plane:6443` URL.
2. **The provider reads `DOCKER_HOST` from process env at provider-init time.** That works for one-host-per-bnk-forge-instance setups, but breaks per-project remote-host selection. `local-exec`'s `environment = {}` argument lets us inject `DOCKER_HOST` per-resource without touching bnk-forge core.

So this module shells out to the `kind` CLI from a `terraform_data` resource (with `local-exec` create/destroy provisioners), and pulls the kubeconfig via a `data "external"` block that calls `kind get kubeconfig --internal`. Same pattern as `kind-cluster-register`.

Trade-off: lose declarative state for the cluster object itself. Acceptable because the manifest declares `supports_drift: false` and kind clusters are cheap to recreate.

## Inputs

All inputs are optional; the module ships sensible defaults.

| Name | Default | Notes |
| ---- | ------- | ----- |
| `cluster_name` | `bnk` | kind cluster name. Also used as the BNK `cluster_id`. |
| `ssh_user`, `ssh_host` | `""`, `""` | Auto-derive `DOCKER_HOST=ssh://${ssh_user}@${ssh_host}` when both are set. Wired from bare-metal credential template. |
| `docker_host` | `""` | Explicit DOCKER_HOST override; takes precedence over `ssh_user`/`ssh_host`. |
| `kind_node_image` | `""` | Provider default when empty. |

The kind topology (1 control-plane + 4 workers, dual-stack, default CNI off,
port mappings on the first worker for Grafana 32000→3000 and Prometheus
30000→8088) is pinned in the vendored `payload/kind.yaml` and not currently
exposed as inputs. If you need to vary the topology, fork the module or open a
discussion before adding more knobs.

## Outputs

| Name | Notes |
| ---- | ----- |
| `cluster_id`, `cluster_name`, `cluster_endpoint`, `region` | Standard BNK registration outputs. `region` is the literal string `local-kind`. |
| `kubeconfig` | Base64-encoded in-network kubeconfig (sensitive). bnk-forge auto-registers the cluster from this. |
| `kube_host`, `kube_client_certificate`, `kube_client_key`, `kube_cluster_ca_certificate` | For downstream modules that prefer to wire the `kubernetes` / `helm` providers directly instead of decoding the kubeconfig. |

## State managed

- One kind cluster on the target Docker daemon.
- Five Docker containers (one per kind node).
- The kind cluster's network namespace and bridge.

`tofu destroy` removes all of the above.

## Dependencies

None. This is the entry point for the `bnk-on-kind-create-cluster` blueprint.

## Runtime requirements

- `kind` CLI on `$PATH` in the worker container (also required by `kind-cluster-register`).
- `jq` on `$PATH` (already in the bnk-forge worker image).
- A reachable Docker daemon — local `/var/run/docker.sock` mount, or `DOCKER_HOST` set on the worker, or `ssh_user`+`ssh_host` provided via inputs.

## Local validation

```bash
cd modules/kind-cluster-create
tofu fmt -check
tofu validate
jq -e . bnkforge.pack.json > /dev/null
```

For a real plan/apply, point at any reachable Docker daemon. The provisioners
will skip cluster creation if a kind cluster with the same name already exists.
