# BNK Forge — kind Cluster

Forge-ready content for installing BNK on a [kind](https://kind.sigs.k8s.io/)
cluster. Intended for fast, low-resource POCs and developer loops on the same
host that runs BNK Forge — or, optionally, on a remote host reachable over
`DOCKER_HOST` (including `ssh://user@host`).

Two blueprints chain the same modules end-to-end:

1. **Get a cluster** — either provision a new kind cluster (`bnk-on-kind-create-cluster`) or reference an existing one (`bnk-on-kind-existing-cluster`).
2. **Label two workers as DPU-equivalent.** kind doesn't have real DPUs; FLO/TMM is satisfied by `app=f5-tmm` labels and a `dpu=true:NoSchedule` taint on two worker nodes.
3. **Install cert-manager** + the BNK self-signed cluster issuer.
4. **Install the F5 Lifecycle Operator (FLO).**
5. **Deploy a CNEInstance.**
6. **Apply the BNK License.**

Each step is its own Forge-ready module; the two blueprints share the same
downstream chain, so the only difference between them is how the cluster
shows up — fresh from `kind create` versus an existing kind cluster the user
brought themselves.

## Modules

| Module path | Purpose |
| ----------- | ------- |
| `modules/kind-cluster-create` | Create a kind cluster by shelling out to the `kind` CLI from a `terraform_data` + `local-exec` resource (the `tehcyx/kind` provider doesn't support per-deploy `DOCKER_HOST` selection or in-network kubeconfig output, so we drive `kind` directly). Uses a vendored `kind.yaml` (1 control-plane + 4 workers, dual-stack, default CNI off). Emits the BNK registration outputs (`cluster_name`, `cluster_endpoint`, base64 `kubeconfig`, `region="local-kind"`). |
| `modules/kind-cluster-register` | Reference an existing kind cluster by name, read its `kind get kubeconfig --internal` output, and emit the same registration outputs. |
| `modules/kind-cluster-label-dpu-nodes` | Label two worker nodes `app=f5-tmm` and taint them `dpu=true:NoSchedule` so FLO/TMM scheduling matches the f5-bnk-udf lab pattern. Defaults to `bnk-worker2` and `bnk-worker3`. |
| `modules/kind-cluster-install-cert-manager` | Jetstack `cert-manager` Helm chart + the self-signed + `bnk-ca-cluster-issuer` chain BNK expects. |
| `modules/kind-cluster-install-flo` | Thin wrapper around the F5 Lifecycle Operator Helm chart (`oci://repo.f5.com/charts/f5-lifecycle-operator`). Materializes the FAR pull secret from the `far_auth_key` project secret and renders FLO values with the `jwt_token` project secret. No IBM trusted-profile / COS dependency. |
| `modules/kind-cluster-cneinstall` | Apply a `CNEInstance` CR with kind-appropriate defaults (no Multus `networkAttachments`, `pseudoCNI=false`, `dynamicRouting=false`, `demoMode=true`). |
| `modules/kind-cluster-license` | Apply the BNK License CR using the `jwt_token` project secret. `use_cos_bucket=false` — no IBM Cloud Object Storage path. |

## Blueprints

| Blueprint | Module chain |
| --------- | ------------ |
| `blueprints/bnk-on-kind-create-cluster` | `cluster-create` → `label-dpu-nodes` → `cert-manager` → `flo` → `cneinstance` → `license` |
| `blueprints/bnk-on-kind-existing-cluster` | `cluster-register` → `label-dpu-nodes` → `cert-manager` → `flo` → `cneinstance` → `license` |

## Project type

| Blueprint | Recommended project type | Why |
| --------- | ------------------------ | --- |
| `bnk-on-kind-create-cluster` | **Bare-metal** (or any project with no credential template) | The bare-metal project's optional SSH credential template (`ssh_user`, `ssh_host`, …) maps directly to `DOCKER_HOST=ssh://${ssh_user}@${ssh_host}` for remote-host kind installs. Leave the SSH template empty to deploy on the local bnk-forge host via `/var/run/docker.sock`. |
| `bnk-on-kind-existing-cluster` | **Existing Kubernetes** | Standard Stage 2 pattern: register the kind kubeconfig as a project cluster first, then deploy. |

## Local vs remote Docker host

Both create flows share one optional input: `docker_host`. When empty (the
default), the `tehcyx/kind` provider talks to the local Docker socket
(`/var/run/docker.sock`, mounted into the bnk-forge worker container). When
populated — either by user input on the Deploy form or, more commonly,
auto-derived from the bare-metal project's SSH credential template — it's
forwarded to the provider as `DOCKER_HOST`. Common values:

- `ssh://user@host` — runs `kind` against a remote Docker daemon over SSH.
- `tcp://host:2375` — direct TCP, suitable when the remote daemon exposes a TLS or trusted endpoint.

## BNK registration outputs

Both `kind-cluster-create` and `kind-cluster-register` emit:

- `cluster_name`
- `cluster_id` (alias of `cluster_name` for kind — kind has no separate ID)
- `cluster_endpoint`
- `region` (literal `local-kind`)
- `kubeconfig` (base64-encoded, sensitive)

bnk-forge auto-registers the cluster on first scan after apply — no manual step.

## Project secrets

Both blueprints declare two `project_secret` prerequisites:

- `far_auth_key` — base64-encoded contents of the F5 Artifacts Registry auth tarball (`f5-far-auth-key.tgz`). Used to materialize the `far-secret` `dockerconfigjson` Secret in `f5-operators` and `default`.
- `jwt_token` — F5 BNK subscription JWT. Templated into FLO values and the License CR.

Both are stored encrypted by bnk-forge and injected at apply time without
serializing into plan or task output.

## Import into BNK Forge

1. Add this repository as both a **Module Source** and a **Blueprint Source** and sync it.
2. Add the two project secrets (`far_auth_key`, `jwt_token`) to the project that will deploy.
3. Import the blueprint that fits your scenario:
   - `bnk-on-kind-create-cluster` to create a new kind cluster.
   - `bnk-on-kind-existing-cluster` to install BNK onto a kind cluster that already exists.
4. Deploy. After apply succeeds, BNK Forge auto-registers the kind cluster.

## Repo layout

```text
bnk-forge-kind-cluster/
  modules/
    kind-cluster-create/             # bnkforge.pack.json, *.tf, payload/kind.yaml
    kind-cluster-register/
    kind-cluster-label-dpu-nodes/
    kind-cluster-install-cert-manager/
    kind-cluster-install-flo/
    kind-cluster-cneinstall/
    kind-cluster-license/
  blueprints/
    bnk-on-kind-create-cluster/forge-blueprint.json
    bnk-on-kind-existing-cluster/forge-blueprint.json
```
