kind: stack
description: |
  DRAFT (Wave 0 spike) — kubestellar-hive stack.

  WHAT UPSTREAM ACTUALLY SHIPS (evidence for the #113 "one image or
  several?" question — this target is the plan's named unsolved example):

  kubestellar/hive (CNCF, "AI agent orchestration") publishes THREE images
  from .github/workflows/docker.yml, none distroless/scratch/ko/Wolfi:

  1. ghcr.io/kubestellar/hive (v2/Dockerfile, base node:24-slim): the
     "Go daemon + Node proxy + ttyd" trio this spike targets — PLUS a full
     agent workstation: tmux built from source, su-exec compiled in,
     npm-installed AI CLIs (@github/copilot, @anthropic-ai/claude-code,
     @openai/codex, goose, bobshell, @kubestellar/pluk), python3 + pip +
     litellm, gh CLI, a full Go toolchain for agents, iptables/gosu/bash.
     v2/deploy/entrypoint.sh starts `hive` (:3002), `node server.js`
     (:3001 auth/static shim over the Go API) and a ttyd respawn loop
     (:7681 wrapping ttyd-tmux.sh) as ONE supervised unit sharing /data
     (MITM proxy CA, runtime config, agent homes) and the manager's tmux
     sockets. Splitting the trio into separate containers means
     re-architecting upstream (shared tmux, shared CA bundle file, shared
     config paths, one cleanup trap) — so for THIS workload the answer is:
     ONE image for the trio, but the workload decomposes into the three
     images upstream already ships.
  2. ghcr.io/kubestellar/hive-hub (v2/Dockerfile.hub, base alpine:3.21):
     the Go daemon alone (HIVE_MODE=hub) + kubectl + ca-certs + curl.
     The only genuinely distroless-able sub-target.
  3. ghcr.io/kubestellar/hive-contributor (v2/Dockerfile.contributor,
     base debian:bookworm-slim): contributor relay + agent CLIs.

  SCOPE VERDICT (rule 3): technically IN — no upstream image is
  distroless/scratch/ko/Wolfi. But the main image is shell-ful BY DESIGN
  (agents run in tmux with bash; ttyd serves a shell), so the full image
  belongs to the nspawn machine-image lane (the repo's one documented
  non-distroless exception), NOT this distroless lane. A distroless
  kubestellar-hive makes sense only as the hub variant.

  WHAT THIS STACK CONTAINS (draft): the Go binaries via hive-bin.bst
  (go_module IS now enabled in project.conf — #145 closed #144 — so the
  load-time gate is open; what remains there is `bst source track` to fill
  the 26 untracked go_module refs) and the ttyd chain (libwebsockets.bst +
  ttyd.bst — buildable from FSDK components).
  What it CANNOT contain on today's grid: the Node dashboard proxy —
  FSDK has NO node component (checked components/ at the pinned junction
  ref), buildstream-plugins-community 2.3.1 has NO npm source plugin, and
  the RE grid build phase has NO network, so `npm install express
  http-proxy-middleware` cannot run and no vendored node_modules tarball
  exists upstream. Wave 4 options: (a) upstream publishes a vendored
  node_modules tarball; (b) hand-declare the npm tree as tarball sources
  (express@5 has ~60 transitive packages — toil, no lockfile->YAML
  generator); (c) drop the proxy and let the Go daemon serve :3002
  directly (it already serves the API + can embed static files — the
  proxy is a thin auth shim; dropping it changes auth behavior, needs
  upstream discussion).

  MEASURED BUILD STATUS (2026-08-09, ghost BuildBarn grid):
  - kubestellar-hive/ttyd.bst (+ libwebsockets.bst): full graph RESOLVES
    (`bst show` SUCCESS), proving cmake/ninja/gcc/json-c/openssl/zlib all
    exist in FSDK at the pinned junction ref. `bst build ttyd.bst` got as
    far as libwebsockets COMPILING SUCCESSFULLY on a grid worker (12m41s);
    the run then failed downloading the result artifact from grid storage:
        Failed to obtain input file "usr/lib/debug/usr/bin/ctest.debug":
        Shard 1: error reading from server: connection reset by peer
    Deterministic across two runs (same blob) — grid storage shard issue
    (ctest.debug belongs to cmake's debug split staged into the build
    sandbox), NOT an element error. Retry when the grid CAS is healthy.
  - kubestellar-hive/hive-bin.bst: WAS blocked at load by an unregistered
    go_module plugin; that gate is open as of #145 (see hive-bin.bst for
    the historical error and the conditions that would bring it back).
    Not yet re-measured since: its 26 go_module sources are still
    untracked (no `ref:`), so the next step is `bst source track` and then
    a grid build — neither has been done, and this element must not be
    described as spiked until both are.

depends:
  - base/base-stack.bst
  - kubestellar-hive/hive-bin.bst
  - kubestellar-hive/ttyd.bst
