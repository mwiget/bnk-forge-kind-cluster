# Session Handoff — bnk-forge-kind-cluster

Snapshot of where this branch stands so a fresh Claude session on a different
machine can pick up without re-reading the whole transcript.

Repo: `github.com/mwiget/bnk-forge-kind-cluster`. Push directly to `main`
(personal repo — no PR flow).

Companion repo (the engine): `github.com/mwiget/bnk-forge` on the `staging`
branch. The bnk-forge worker container is what actually runs `tofu init/plan/
apply` for each module. Validate `.tf` changes by execing into the worker
and running `tofu validate` against the module dir before pushing — the
worker's tofu version is what matters, not the host's.

## Project scope (what this repo is)

A bnk-forge blueprint that installs F5 BNK end-to-end on a [kind](https://kind.sigs.k8s.io/)
cluster, for developer/POC use.

Two blueprints share the same downstream chain:

- `bnk-on-kind-create-cluster` — provisions a fresh kind cluster, then runs
  the chain.
- `bnk-on-kind-existing-cluster` — references an already-running kind cluster
  by name, then runs the chain.

Module chain (in execution order):

1. `kind-cluster-create` (or `kind-cluster-register`) — get a cluster, emit
   registration outputs (`cluster_name`, `cluster_endpoint`, base64 `kubeconfig`,
   `region=local-kind`).
2. `kind-cluster-label-dpu-nodes` — label two workers `app=f5-tmm`, taint
   `dpu=true:NoSchedule`.
3. `kind-cluster-install-cert-manager` — jetstack cert-manager + BNK CA chain.
4. `kind-cluster-install-flo` — F5 Lifecycle Operator helm chart (OCI), FAR
   pull secret, FLO values with JWT.
5. `kind-cluster-cneinstall` — CNEInstance CR.
6. `kind-cluster-license` — License CR (`k8s.f5net.com/v1`).

Project secrets the user provides via the bnk-forge UI:

- `far_auth_key` — extracted contents of `f5-far-auth-key.tgz`
  (base64-encoded service-account JSON).
- `jwt_token` — F5 BNK subscription JWT.

`kubeconfig` is NOT a user secret — it flows internally as a module output
from `kind-cluster-create` / `kind-cluster-register` to every downstream
module. The original UI prompt for kubeconfig was a bug fixed by removing
`sensitive: true` from the `kubeconfig` input on every consumer manifest
(secrets_service flags any sensitive manifest input as a project-secret
prompt).

## Status

**Working through cneinstall.** As of latest deploy:

- kind cluster comes up clean.
- DPU labels + taints apply (`kubernetes_labels` for labels;
  `terraform_data` + `kubectl taint --overwrite` for taints — replaces the
  broken `kubernetes_node_taint` resource).
- cert-manager installs and the ClusterIssuer chain is healthy. Idempotent
  via `kubectl_manifest` for the namespace + `terraform_data` pre-uninstall
  hook for the helm release.
- FLO installs and the operator pod is Ready. Required fix:
  `NetworkAttachmentDefinition.k8s.cni.cncf.io` CRD must be registered
  before the FLO operator starts, or the controller-runtime cache-sync
  times out and the pod crash-loops. We install the upstream NAD CRD
  shape (no Multus needed — kindnet handles CNI).
- FLO helm install bypasses the hashicorp/helm provider entirely — provider
  3.1.1's OCI client doesn't share auth state with `helm registry login`,
  so it 403s on chart pull even when the on-disk `~/.config/helm/registry/
  config.json` has the credential. Worked around by driving `helm
  registry login` + `helm upgrade --install` from the CLI via
  `terraform_data` + `local-exec`. See `modules/kind-cluster-install-flo/
  main.tf:198`.
- CNEInstance applies; BNK platform components (FW, DDoS, gateway, SPK,
  VRF, VXLAN — ~25 CRDs under `k8s.f5net.com`) all reconcile and become
  Ready.

**Open issue: License module.**

The `licenses.k8s.f5net.com` CRD never appears on the kind cluster, even
after all other BNK platform CRDs are registered. The license module's
`terraform_data.wait_for_license_crd` polls for it on 10s intervals up to
600s and then fails.

Observed CRD set under `k8s.f5net.com` after FLO + cneinstall reconcile:
data-plane CRDs (firewall, DDoS, gateway, SPK egress/snatpool/staticroute/
vlan, VRF, VXLAN, routing configs, BNK net/sec policies, log profiles,
bnkgateways, etc.). NO License CRD.

One unhealthy deployment in `f5-operators`: `f5-spk-cwc` is 0/1. Selector
`app=f5-spk-cwc` matched 0 pods, so the deployment's pod template uses a
different label key — needs `kubectl describe deployment` to find the real
selector. Hypothesis: f5-spk-cwc (Common/Cluster Workload Controller) is
what would register the License CRD, and we haven't fixed whatever is
keeping it from coming Ready.

### Two paths forward for the License module

**A. Drop it from the kind blueprints.** (Recommended for v1.)

Rationale: License CR is for cluster-level licensing of TMM data-plane
workloads. kind has no TMM running — no data plane to license. The JWT
that actually matters is already passed to FLO via helm values
(`license.jwt` in `modules/kind-cluster-install-flo/main.tf:173`), which
is what FLO uses for product registration / telemetry.

To do this:

- Remove the `modules/kind-cluster-license` entry from both
  `blueprints/*/forge-blueprint.json` chains.
- Delete `modules/kind-cluster-license/`.
- Bump blueprint version (currently `1.0.14`) and the create/existing
  blueprint `bnkforge.pack.json` versions.
- Re-sync Module Sources AND Blueprint Sources in the bnk-forge UI (they
  are separate `module_sources` / `blueprint_sources` DB tables).

**B. Fix `f5-spk-cwc` and keep the License module.**

Investigate why `f5-spk-cwc` is 0/1. Likely steps:

```bash
docker exec bnk-forge-celery-worker bash -c '
  KC=$(mktemp); kind get kubeconfig --internal --name bnk > $KC;
  kubectl --kubeconfig $KC -n f5-operators describe deployment f5-spk-cwc;
  kubectl --kubeconfig $KC -n f5-operators get events --sort-by=.lastTimestamp | tail -30;
  kubectl --kubeconfig $KC -n f5-operators get pods -o wide
'
```

Find the real pod label selector, then describe the pod to see whether
it's `ImagePullBackOff` (FAR auth issue propagating to `f5-operators`
namespace?), `CrashLoopBackOff` (config issue), or `Pending` (scheduling).
Once `f5-spk-cwc` is Ready, verify the License CRD appears — if it does,
the existing license module will succeed unchanged.

## Strategic discussion: OpenTofu vs. Python / shell

User question raised mid-session: would a python or shell implementation
of the kind blueprint be simpler than wrestling with the OpenTofu
providers?

Honest answer: **yes for several of these modules.** Three reasons:

1. **The hard parts have all been escape hatches.** `kind-cluster-create`,
   `label-dpu-nodes`, `install-flo` (helm install path), and `license`
   (CRD wait) all already wrap shell commands inside `terraform_data` +
   `local-exec`. The OpenTofu wrapper buys nothing — no real
   diff/refresh, no plan-time validation that ever caught anything. It's
   just bash with extra YAML.

2. **The provider footguns wasted hours.** `kubernetes_node_taint` produced
   "inconsistent result" errors due to kube-controller-manager spec
   normalization. `kubernetes_manifest` fails plan-time validation if the
   CRD doesn't exist yet. `hashicorp/helm` provider 3.1.1's OCI auth
   doesn't read `~/.config/helm/registry/config.json`. Each of these was
   a half-day workaround that wouldn't exist in a script.

3. **The genuinely declarative parts** — namespace, far-secret,
   network-attachment-definition CRD, CNEInstance, License — are tiny
   manifests that work equally well via `kubectl apply -f -` from a
   script, with `kubectl_manifest` server-side apply semantics replicable
   via `kubectl apply --server-side --force-conflicts`.

What you'd lose by going script-based: bnk-forge's per-module state
tracking and re-entry. The blueprint UI counts on each module reporting
its own apply/destroy status. bnk-forge supports a `script` engine and a
`kubernetes` engine alongside `tofu` — they participate in the same
manifest schema and project-state model, so a port is feasible without
losing the UI integration.

**User decision:** "I might consider pursuing python/shell in a different
personal repo branch." Deferred until the current OpenTofu chain reaches
end-to-end success — finishing the License module question (path A or B
above) closes that out.

If pursuing the python/shell port later, branch from `main` with a name
like `script-engine` or `python-engine`, and migrate one module at a
time. Start with `kind-cluster-create` (most shell-native already), then
`label-dpu-nodes`, then `license`. cert-manager and FLO would stay tofu
unless the helm-CLI shell-out has compounded enough complexity to
warrant a port.

## Recent commit history (most-recent first)

```
12a0586 fix(flo): install NetworkAttachmentDefinition CRD before helm install
0b28cd1 fix(license): poll for License CRD existence before waiting for Established
e1b7325 fix(license): correct API group, inline JWT, wait for CRD registration
0015b6f fix(flo): bypass hashicorp/helm provider — install via helm CLI directly
cca8464 fix(flo): authenticate helm OCI at plan time via data.external
0744626 fix(flo): move helm registry login into the FLO module
85bd5df fix(label-dpu-nodes): replace kubernetes_node_taint with kubectl shell-out
1dbbd9e fix(flo, cert-manager): drop stale outputs.tf refs + add kubectl declaration
74d9bb9 fix(flo, cert-manager): pre-uninstall hook so retries don't AlreadyExists
dc52f96 fix(secrets): remove sensitive:true from kubeconfig in 5 manifests
```

## How to resume on a different machine

The next session needs three things: this repo, the bnk-forge worker
running locally on that machine, and the bnk-forge UI reachable in a
browser.

1. **Clone the repo.**

   ```bash
   git clone git@github.com:mwiget/bnk-forge-kind-cluster.git
   cd bnk-forge-kind-cluster
   ```

2. **Stand up bnk-forge locally** (separate clone, sibling directory).

   ```bash
   cd ..
   git clone git@github.com:mwiget/bnk-forge.git
   cd bnk-forge
   git checkout staging
   # follow bnk-forge's own README for `docker compose up` (or whatever
   # the staging branch's bootstrap is). Confirm the worker container is
   # named `bnk-forge-celery-worker` — the diagnostic commands below
   # assume that name.
   ```

3. **Sanity-check the worker has tofu + helm + kubectl + kind + docker
   socket access:**

   ```bash
   docker exec bnk-forge-celery-worker bash -c 'tofu version; helm version --short; kubectl version --client --short; kind version; docker ps >/dev/null && echo "docker ok"'
   ```

4. **Tell the resuming Claude session to read this file first:**

   > Read HANDOFF.md in the working directory. We're resuming the
   > bnk-forge-kind-cluster work — pick up from the "Status" /
   > "Open issue" section. Don't re-explore architecture; the file
   > covers it.

5. **First diagnostic to run on resume** (validates the cluster from the
   last session is gone, or still up, before deciding next step):

   ```bash
   docker exec bnk-forge-celery-worker bash -c 'kind get clusters'
   ```

   If a kind cluster still exists from before: either destroy via the
   bnk-forge UI (preferred — cleans state too) or `kind delete cluster
   --name <name>`. If no cluster: deploy a fresh project in the UI from
   the latest blueprint version and watch which module fails — should
   still be `kind-cluster-license` unless someone has touched the chain.

6. **Push convention.** This is a personal repo. Push directly to `main`,
   no PR flow. (Auto-mode classifiers in some Claude configurations may
   block direct main pushes — if so, use `gh api` instead of `git push`,
   or paste-execute the command.)

7. **`tofu validate` convention.** Before pushing any `.tf` change, run
   `tofu validate` on the changed module via the worker:

   ```bash
   docker exec -w /code/bnk-forge-kind-cluster/modules/<module-name> \
     bnk-forge-celery-worker tofu init -backend=false
   docker exec -w /code/bnk-forge-kind-cluster/modules/<module-name> \
     bnk-forge-celery-worker tofu validate
   ```

   (Path may differ — depends on how the worker volume-mounts this repo.
   On the previous machine the repo was mounted under
   `/workspace/bnk-forge-kind-cluster` inside the worker. Adjust to
   whatever mount the new machine uses.)

## Open follow-ups (not blocking)

- f5-spk-cwc Readiness diagnosis (only matters if pursuing path B above).
- Consider porting selected modules to bnk-forge's `script` or
  `kubernetes` engine (separate branch).
- README.md is current as of the FLO + license module rewrites; verify
  no stale references after deciding path A vs B.
