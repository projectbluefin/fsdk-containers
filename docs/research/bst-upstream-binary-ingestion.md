# BuildStream Ingestion of Upstream Binaries With No FSDK Component

Research output resolving [#115](https://github.com/projectbluefin/fsdk-containers/issues/115). Parent map: [#113](https://github.com/projectbluefin/fsdk-containers/issues/113).

**Build from upstream source. The mechanism already exists and this repo is one line away from it.**

### The answer: the `go_module` source plugin

`buildstream-plugins-community` ships a `go_module` source plugin. It fetches Go modules during `bst source fetch` / tracking and stages a generated `vendor/` tree plus `vendor/modules.txt`, so the **build sandbox stays offline** — which is what BuildStream requires, since sandboxed builds have no network.

This is not theoretical: **freedesktop-sdk already uses it in production.** `components/go-md2man.bst` combines an upstream `git_repo` source with `go_module` sources and builds against FSDK's `components/go.bst`.

### This repo is already 95% of the way there

`elements/plugins/buildstream-plugins-community.bst` already junctions **`buildstream_plugins_community-2.3.1`** — the exact version carrying `go_module`. `project.conf:60-65` registers only `git_repo` and `patch_queue` from that junction.

**Enabling `go_module` is adding one line to the `sources:` list under that plugin origin in `project.conf`.** No new dependency, no new junction, no version bump.

### Recommended pattern

- Pinned upstream `git_repo` source + pinned `go_module` sources.
- Build flags: `GOFLAGS=-mod=vendor`, `GOTOOLCHAIN=local`, `-trimpath`, `-buildvcs=false`.
- **Prefer an upstream-committed `vendor/` tree where one exists** — it removes the per-module YAML entirely and is the cheapest path per catalog image.
- `CGO_ENABLED=0` for the static lane (cgo-free projects); this is what the repo's existing `static` stack already targets. cgo projects keep `CGO_ENABLED=1`, take FSDK build/runtime deps, and ship dynamic.

### Rejected: prebuilt binary import

A pinned `remote`/`tar` release binary is deterministic **as an input**, but the attestation then covers only download/assembly and the FSDK rootfs — **not the compiler, the dependencies, or the build of the executable**. That guts the provenance claim which is this catalog's entire value proposition. Acceptable as a temporary fallback for a single blocked target; **not** the catalog default.

### Outstanding

No authoritative `go.sum` → source-YAML **generator** was found — only the plugin's own per-module tracking. At catalog scale, per-module YAML is a real cost. Preferring upstream-vendored projects sidesteps it; a generator may be worth building later. Graduated to the map as fog, not blocking.

### Scope note

Per the audit in #114, this path matters **less** than assumed at charting — most surviving catalog targets are enterprise runtimes backed by existing FSDK components. It remains required for Volcano, KubeStellar Hive and Falco.

<sub>Sources: FSDK `elements/components/go-md2man.bst`; FSDK `project.conf`; `buildstream_plugins_community/sources/go_module.py` @ 2.3.1; BuildStream sandboxing docs (2.5); `pkg.go.dev/cmd/go` on `-mod=vendor`, `-trimpath`, `-buildvcs`. Local verification: `project.conf:60-65`, `elements/plugins/buildstream-plugins-community.bst`.</sub>

## Concrete pattern

Enable the plugin in `project.conf` (the junction is already present at 2.3.1):

```yaml
plugins:
  - origin: junction
    junction: plugins/buildstream-plugins-community.bst
    sources:
      - git_repo
      - patch_queue
      - go_module      # <-- the one-line change
```

Element shape, preferring an upstream-committed `vendor/` tree where one exists:

```yaml
kind: manual
build-depends:
  - freedesktop-sdk.bst:components/go.bst
depends:
  - base/base-stack.bst

sources:
  - kind: git_repo
    url: github:volcano-sh/volcano.git
    track: v*
    ref: <pinned>

variables:
  goflags: "-mod=vendor -trimpath -buildvcs=false"

environment:
  GOFLAGS: "%{goflags}"
  GOTOOLCHAIN: local
  CGO_ENABLED: "0"       # static lane; use "1" + FSDK deps for cgo projects

config:
  build-commands:
    - go build -o vc-scheduler ./cmd/scheduler
  install-commands:
    - install -Dm755 vc-scheduler "%{install-root}%{bindir}/vc-scheduler"
```

Where upstream does **not** vendor, add one pinned `go_module` source per module. That is
the per-module YAML cost noted above, and the reason upstream-vendored projects are
preferred at catalog scale.
