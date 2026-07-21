---
name: remote-execution
description: >
  How local/agent BuildStream builds in this repo are submitted to the ghost
  cluster's BuildBarn remote-execution grid instead of running on the local
  machine. Use when running `just build`/`just bst`, debugging RE failures,
  or deciding when local execution is acceptable.
metadata:
  type: runbook
---

# BuildStream Remote Execution on the Ghost Cluster

## Policy

**Local and agent builds MUST run on the ghost cluster's BuildBarn grid, not
on the local machine.** The `just bst` wrapper enforces this: it injects a
`remote-execution:` config by default, and it **fails** if the cluster is
unreachable rather than silently falling back to local execution. Local
execution is an explicit opt-in (`BST_LOCAL=1`), never a fallback.

This mirrors the factory-wide rule (see the ghost cluster ops skill): never
run heavy workloads on workstations when the cluster exists to absorb them.

## How it works

`just bst` (the wrapper every recipe goes through):

1. Unless `BST_LOCAL=1` or running in GitHub Actions, it:
   - checks the BuildBarn frontend Service exists
     (`kubectl get svc frontend -n buildbarn`, `KUBECONFIG` defaults to
     `~/.kube/bluespeed.yaml`) — **hard-fails if not**;
   - starts `kubectl port-forward -n buildbarn svc/frontend 18980:8980` for
     the duration of the command;
   - writes `.bst-re.conf` (git-ignored) pointing
     `execution-service`/`storage-service`/`action-cache-service` at
     `grpc://127.0.0.1:18980`;
   - passes `--config /src/.bst-re.conf` to `bst` inside the bst2 container
     (which runs with `--network=host`, so `127.0.0.1:18980` resolves to the
     port-forward).
2. Build actions are scheduled by the BuildBarn scheduler onto the `worker-*`
   pods (distributed across ghost + exo-0). Sources/artifacts flow through the
   in-cluster CAS; the project's public pull caches (`gbm.gnome.org`,
   `cache.projectbluefin.io:11001`) still serve cached elements so most
   elements are pulled, not built.

Success evidence in the log: `Waiting for the remote build to complete` per
built element. If you instead see local sandbox staging messages for build
actions, RE is not active.

## Endpoints

| Endpoint | Auth | Used by |
| -------- | ---- | ------- |
| `grpc://frontend.buildbarn.svc.cluster.local:8980` | none (in-cluster) | Argo workflow pods (`bst-qa-pipeline`, `dakota-build-pipeline`) |
| `127.0.0.1:18980` → port-forward to the above | kubeconfig | `just bst` from workstations/agents (this repo) |
| `cache.projectbluefin.io:11002` | **mTLS** (`CASD_CLIENT_CERT`/`CASD_CLIENT_KEY`) | dakota GitHub CI. **Do not point this repo at it without the client cert** — anonymous gRPC gets `StatusCode.UNIMPLEMENTED / http2 404`. |

## Exceptions (when local execution is correct)

- **`BST_LOCAL=1 just build`** — explicit opt-out for offline work or when the
  grid is down. Announce it; it is a degraded mode, not a normal one.
- **GitHub Actions CI** — auto-detected via `GITHUB_ACTIONS=true`, always
  local. Two reasons: CI builds each arch natively on matched runners
  (`ubuntu-24.04` / `ubuntu-24.04-arm`) while the BuildBarn grid is
  x86_64-only; and runners have no kubeconfig for the LAN cluster.
- **aarch64 builds** — no aarch64 RE workers exist yet; local (or CI ARM
  runner) is the only path.

## Failure modes

| Symptom | Cause | Fix |
| ------- | ----- | --- |
| `ERROR: ghost cluster BuildBarn frontend unreachable` | no kubeconfig / cluster down / off-LAN | fix cluster access, or `BST_LOCAL=1` deliberately |
| `Failed to query action cache: StatusCode.UNIMPLEMENTED (... 404)` | pointed at an mTLS endpoint (e.g. `:11002`) without client certs | use the port-forward path; never the external endpoint from this repo |
| build hangs at `Waiting for the remote build to complete` | grid saturated, or worker pods down | `kubectl get pods -n buildbarn`; check the `ghost-heavy-compute` mutex — dakota builds queue on the same grid |
| port-forward dies mid-build (long builds) | kubectl port-forward is not resilient | rerun; bst resumes from CAS. |

## Verifying where a build ran

```bash
# In the element build log (~/.cache/buildstream/logs/...):
grep "Waiting for the remote build" <log>        # present ⇒ ran on the grid

# Grid-side:
KUBECONFIG=~/.kube/bluespeed.yaml kubectl top pods -n buildbarn   # worker CPU active
```

## Etiquette

- The grid is shared with dakota builds (`ghost-heavy-compute` mutex on the
  Argo side). Check `argo list -n argo` before firing large builds.
- `.bst-re.conf` is generated per-invocation and git-ignored — never commit it.
