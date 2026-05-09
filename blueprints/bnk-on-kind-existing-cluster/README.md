# BNK on kind — existing cluster

Stage 2 blueprint. Installs BNK onto a kind cluster that already exists.

## What you get

1. The kind cluster is referenced (not created) and emits BNK registration outputs.
2. Two workers (`bnk-worker2`, `bnk-worker3` by default) are labeled `app=f5-tmm` and tainted `dpu=true:NoSchedule` (DPU emulation).
3. cert-manager is installed and the `bnk-ca-cluster-issuer` chain is created.
4. The F5 Lifecycle Operator is installed with the FAR pull secret + license JWT.
5. A `CNEInstance` CR is applied with kind-appropriate defaults.
6. A BNK `License` CR is applied.

## Project setup

- Project type: **Existing Kubernetes** (or any project with the kind cluster's kubeconfig registered).
- Project secrets:
  - `far_auth_key` — extracted contents of `f5-far-auth-key.tgz`.
  - `jwt_token` — F5 BNK subscription JWT.
- Optional: bare-metal credential template populated with SSH host/user if the kind cluster lives on a remote Docker daemon. The blueprint maps those fields to `DOCKER_HOST=ssh://user@host`.

## After apply

bnk-forge auto-registers the kind cluster on first scan. Check the **Kubernetes** page to confirm. FLO and CNEInstance pods should be Ready in `f5-operators`.

## Lifecycle stage

Stage 2 — installs the BNK platform onto an existing cluster.
