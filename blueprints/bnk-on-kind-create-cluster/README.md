# BNK on kind — create cluster

Stage 1 + 2 hybrid blueprint. Provisions a kind cluster from scratch on the
target Docker daemon and installs BNK on top of it. End-to-end one-click.

## What you get

1. A new kind cluster (1 control-plane + 4 workers, dual-stack, default CNI off — defined by the vendored `kind.yaml`).
2. Two workers labeled `app=f5-tmm` and tainted `dpu=true:NoSchedule` (DPU emulation).
3. cert-manager + the `bnk-ca-cluster-issuer` chain.
4. F5 Lifecycle Operator with FAR pull secret + license JWT.
5. A `CNEInstance` CR with kind-appropriate defaults.
6. A BNK `License` CR.
7. Auto-registration of the new cluster in bnk-forge.

## Project setup

| Field | Value |
| ----- | ----- |
| Project type | **Bare-metal** (or any project with no credential template) |
| Project secrets | `far_auth_key`, `jwt_token` |
| Optional credential template | Bare-metal SSH (host, user, key) — turns the blueprint into a remote-host install via `DOCKER_HOST=ssh://user@host` |

For a purely local install, leave the bare-metal SSH template empty. The
`tehcyx/kind` provider talks to `/var/run/docker.sock` mounted into the
bnk-forge worker container.

## Local vs remote

| Scenario | Bare-metal SSH template | Effective DOCKER_HOST |
| -------- | ----------------------- | --------------------- |
| Local kind on the bnk-forge host | empty | _(unset — local socket)_ |
| Remote kind on a Linux server | `ssh_user=ubuntu`, `ssh_host=lab.local` | `ssh://ubuntu@lab.local` |
| Remote kind on a daemon over TCP | empty SSH; set the explicit `docker_host` input | `tcp://lab.local:2375` |

## Compose override

For local installs, the bnk-forge worker needs `/var/run/docker.sock` mounted.
The auto-generated `docker-compose.override.yml` in `bnk-forge` already does
this for the backend; extend the override to the worker service before
running this blueprint:

```yaml
services:
  worker:
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock
```

## After apply

bnk-forge auto-registers the kind cluster on first scan. FLO and CNEInstance
pods should be Ready in `f5-operators`.

## Lifecycle stage

Stage 1 — provisions the target environment. (Plus the Stage 2 install
chain, since for kind the two stages are bundled into one user-facing
blueprint.)
