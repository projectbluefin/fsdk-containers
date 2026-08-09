---
name: remote-execution
version: "1.0"
last_updated: 2026-08-08
id: remote-execution
one_line_purpose: Run BuildStream builds on the ghost cluster BuildBarn remote-execution grid.
entry_point: docs/skills/remote-execution.md
category: ci-ops
mcp_compliance_level: partial
optimization_status: draft
status: active
dependencies: []
tags: [buildstream, remote-execution, buildbarn, cluster]
description: "How local/agent BuildStream builds in this repo are submitted to the ghost cluster's BuildBarn remote-execution grid instead of running on the local machine. Use when running `just build`/`just bst`, debugging RE failures, or deciding when local..."
metadata:
  type: runbook
---

# BuildStream Remote Execution on the Ghost Cluster

## When to Use

- Running `just build`, `just bst`, or any recipe that wraps `bst` locally or
  as an agent
- Debugging a build that fails at `Failed to query action cache` or hangs at
  `Waiting for the remote build to complete`
- Deciding whether a local (`BST_LOCAL=1`) build is acceptable

## When NOT to Use

- CI workflow debugging — CI is deliberately local-execution (see
  [ci-tooling/SKILL.md](ci-tooling/SKILL.md))
- Cache-server (pull-cache) configuration — see
  [custom-builds-and-caching.md](custom-builds-and-caching.md); RE and
  artifact caching are separate mechanisms

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
| `Failed to obtain input file "...": Shard N: Object not found`, raised **after** the remote build already reported success | the default buildtree-caching step walks the whole input tree back against the bb-storage shards; a shard that 404s one input fails the command even though the build itself succeeded | retry — the identical cache key usually succeeds. If it repeats, `BST_FLAGS="--cache-buildtrees never" just bst build <element>` (turned 3 consecutive failures into an immediate success). **Do not suspect your element**: it names a random unrelated input file each time. |

## Data-integrity failure: a build element corrupted the worker file pool

**Symptom.** A build fails parsing a file that should be empty. The canonical
case is Python: `compression/__init__.py` ships as a zero-byte file, but stages
as 23 bytes containing `linuxbrew:100000:65536` (an `/etc/subuid` line), so
`import` dies with a `SyntaxError`. The failing image has nothing to do with
brew, and the same string turning up in an unrelated stdlib file is the
fingerprint.

**Mechanism.** `bb_worker` materialises an action's input root by **hardlinking**
out of a persistent file pool (`worker.jsonnet`: `buildDirectories[0].native`,
`cacheDirectoryPath: /worker/cache`, backed by a **hostPath**, so it survives
pod restart *and* pod deletion). `runner.jsonnet` sets `runCommandsAs: {userId: 0}`
with `chrootIntoInputRoot`, and root ignores the read-only bit. So a build
command that writes **in place** over a staged file rewrites the shared inode:

```sh
echo 'linuxbrew:100000:65536' > "$L/etc/subuid"   # FSDK ships this file EMPTY
```

FSDK's `/etc/subuid` is zero bytes, so that single redirect stored 23 bytes
under the **empty-file digest** — and every zero-byte file staged on that worker
afterwards came back as those 23 bytes. One element, in one image, silently
corrupts every build on the node.

Truncation is the same hazard: `: > "$L/etc/machine-id"` stores zero bytes under
whatever digest machine-id had.

**The rule.** In any element that writes into a **staged** tree (`/layer` in the
oci-builder elements — *not* `%{install-root}`, which starts empty), never
redirect onto a path that may already exist. `rm -f` first, or write to a temp
file and `mv` — `rename()` swaps the directory entry and leaves the pool inode
alone. `rm` itself is safe: it unlinks.

**Diagnosis — find mutated pool entries directly.** Pool entries are named
`1-<digest>-<size>{-,+}x`, so an entry whose on-disk size disagrees with the
size encoded in its own name has been written in place:

```bash
export KUBECONFIG=~/.kube/bluespeed.yaml
for w in worker-fsgmc worker-n8z6v; do
  kubectl exec -n buildbarn $w -c runner -- sh -c \
    'cd /worker/cache && ls -l | awk "{n=\$NF; sz=\$5; split(n,a,\"-\"); if (a[3]!=\"\" && sz+0 != a[3]+0) print sz, n}"'
done
```

Any output means worker-side pool corruption.

**Do NOT wipe the `cas`/`ac` PVCs for this.** It destroys cache shared with
dakota, kills in-flight builds, and fixes nothing — the pool is node-local
hostPath state. (Both CAS PVCs were recreated during this incident and the
symptom persisted, which is what exonerated the CAS.)

**Cluster-side recovery is lab-owned, not ours.** The worker pool is configured
by `manifests/buildbarn-worker.yaml` in `projectbluefin/lab`; that repo's
`docs/skills/cluster-tooling/buildstream.md` already forbids node-local
`hostPath` caches. Do not perform worker surgery from this repo — report it.
Tracking: [projectbluefin/lab#637](https://github.com/projectbluefin/lab/issues/637).

**Structural note.** The hardlink pool assumes actions never modify their
inputs; chroot-as-root breaks that by construction. The virtual/FUSE build
directory is the real mitigation, and `worker.jsonnet` records that the FUSE
experiment failed and the workers must stay on native directories — so until
that is revisited, the discipline above is the only guard.

## What remote execution does not preserve

**File ownership and permission bits do not survive the grid.** The REAPI
captures an action's output tree as content plus a minimal executable bit, so
`chown` and `chmod` run inside a build element are silently lost — a directory
created `0700` and owned `65532:65532` comes back `0755` and root-owned. There
is no error; the element builds green and the wrong thing ships.

This was measured on `postgres` (PGDATA) and applies to every element:

```yaml
# Does NOT work in a build element on the grid:
install-commands:
  - mkdir -p "%{install-root}/var/lib/postgresql/data"
  - chmod 0700 "%{install-root}/var/lib/postgresql/data"   # lost
  - chown 65532:65532 "%{install-root}/..."                # lost
```

Build elements may only create the *scaffold* (the `mkdir`). Anything that
depends on ownership or mode — the data-directory permissions a server refuses
to start without, and the `/etc/passwd` + `/etc/group` entries the non-root
contract requires — belongs in the **OCI script stage**, which runs in-sandbox
when the layer is assembled, not on the grid.

The same constraint explains why `/home/nonroot` ships root-owned: the
BuildStream sandbox cannot `chown` to a UID. Workloads needing a writable home
or data directory mount a volume, which is the Kubernetes-idiomatic answer
anyway.

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

## Common Rationalizations

| Rationalization | Reality |
|---|---|
| "It's a small build, local is faster." | Most elements come from the pull caches either way; the grid only runs what must be built. Local heavy builds on workstations are untracked resource use — the exact thing the cluster exists to absorb. |
| "The cluster check failed, I'll just build locally." | A dead grid is a cluster incident — report it. `BST_LOCAL=1` is a deliberate, announced choice, not an automatic workaround. |
| "I'll point at cache.projectbluefin.io:11002, it's the same grid." | It requires mTLS client certs this repo doesn't have. Anonymous gRPC gets `UNIMPLEMENTED/404` and wastes a debugging session. |

## Red Flags

- Build logs showing local sandbox staging for build actions (no `Waiting for
  the remote build to complete`) when `BST_LOCAL` was not set
- A committed `.bst-re.conf` in a diff
- Any config in this repo referencing `cache.projectbluefin.io:11002`
- `BST_LOCAL=1` used without mention in the handoff/PR

## Verification

- [ ] `just bst --version` prints the `remote execution: ghost cluster` banner
- [ ] Element build log contains `Waiting for the remote build to complete`
- [ ] `kubectl top pods -n buildbarn` shows worker activity during the build
- [ ] `.bst-re.conf` is not tracked (`git ls-files | grep bst-re` → empty)
- [ ] `just verify` still green for the built image

_Config shape verified against `/apache/buildstream` user-config docs
(`remote-execution.{execution,storage,action-cache}-service`,
`connection-config` keys)._
