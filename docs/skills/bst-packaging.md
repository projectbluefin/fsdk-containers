---
name: bst-packaging
version: "1.0"
last_updated: 2026-08-09
id: bst-packaging
one_line_purpose: Build an upstream Go or Rust tool from source when FSDK ships no component for it.
entry_point: docs/skills/bst-packaging.md
category: ci-ops
mcp_compliance_level: partial
optimization_status: draft
status: active
dependencies: []
tags: [buildstream, packaging, go, rust, provenance]
description: "Build an upstream project from source in a BuildStream element when FSDK has no component for it — Go (go_module), Rust (cargo2), and the pre-built-binary fallback."
metadata:
  type: procedure
  context7-sources:
    - /apache/buildstream
---

# Packaging Upstream Projects from Source

## Overview

Most images here are composed from FSDK `components/*` and need no packaging work at
all. This skill is for the other case: **the catalog needs a tool FSDK does not ship.**

The decision is already made. Per
[#115](https://github.com/projectbluefin/fsdk-containers/issues/115), the default is
**build from source with the community source plugins**, because importing a prebuilt
upstream binary guts the provenance claim that is this project's headline value. This
repo already junctions `plugins/buildstream-plugins-community.bst`.

Adapted from `projectbluefin/dakota`'s `packaging-go.md`, `packaging-rust.md`, and
`packaging-binaries.md`. **Dakota's defaults are inverted relative to ours:** dakota
prefers pre-built binaries for its Go tools because it is shipping an OS and the
provenance argument is weaker there. Do not copy that preference across.

## When to Use

- A catalog image needs an upstream Go or Rust tool with no FSDK component
- You are updating the vendored dependency set of an existing source-built element

## When NOT to Use

- FSDK already has a component → just depend on it. Check first:
  `just bst show freedesktop-sdk.bst:components/<name>.bst`
- Upstream already ships an official maintained distroless image → it is **out of
  scope** by catalog rule; consume theirs (see [AGENTS.md](../../AGENTS.md))
- You are assembling an image, not packaging a tool → [add-new-image.md](add-new-image.md)

## Core Process

1. **Confirm FSDK really has no component.** This is the cheapest possible answer.
2. **Confirm a source build is warranted** over consuming an upstream distroless image.
3. **Vendor every dependency into `sources:`.** BuildStream builds are
   network-isolated — there is no `go get` or `cargo fetch` at build time.
4. **Install into merged-usr paths** under `%{install-root}`.
5. **Validate offline completeness** before blaming the language toolchain.

## The network-isolation rule

This is the single fact that shapes every pattern below. **No build step may reach the
network.** Every dependency must be declared as a BuildStream source so it is fetched
during the fetch phase and staged into the sandbox. A build that works on your laptop
and fails in the sandbox with a download error is almost always this.

## Go

Two patterns. **Prefer `go_module` sources** — refs can be updated in place, whereas a
vendored tarball must be regenerated on a host with Go and uploaded separately.

```yaml
kind: make

build-depends:
- freedesktop-sdk.bst:components/go.bst
- freedesktop-sdk.bst:bootstrap-import.bst

variables:
  version: '1.2.3'
  # REQUIRED: dependent elements do not inherit the toolchain's GOROOT_BOOTSTRAP.
  # Without this, remote BuildBarn actions fail with "go: cannot find GOROOT
  # directory" even though the go binary is present in the sandbox.
  GOROOT: "%{libdir}/go"

config:
  build-commands:
  - |
    export GOFLAGS="-mod=vendor"
    go build -o project ./cmd/project/

  install-commands:
  - install -Dm755 project "%{install-root}%{bindir}/project"
  - '%{install-extra}'

sources:
- kind: git_repo
  url: github:owner/project.git
  track: main
  ref: <ref>
- kind: go_module
  url: "github.com/some/dep"
  version: "v1.0.0"
  ref: <sha256>
# ... one go_module entry per dependency
```

Generating the `go_module` block requires running `go mod vendor` upstream and
converting `vendor/modules.txt`. Go binaries are ELF and strip cleanly, so
`strip-binaries` does **not** need disabling.

## Rust

`kind: make` with a `cargo2` source block vendoring every crate offline.

```yaml
kind: make

build-depends:
- freedesktop-sdk.bst:components/rust.bst
- freedesktop-sdk.bst:bootstrap-import.bst

variables:
  version: '1.2.3'
  cargo-home: '%{build-root}/.cargo'
  cargo-opts: '--release --locked'
```

**The `cargo2` block is generated output — never hand-write or hand-edit it.** It is
derived from `Cargo.lock`. After bumping the git ref, enter the build sandbox to get
the new `Cargo.lock`, regenerate, and replace the whole block.

## Pre-built binaries — the fallback, not the default

Justified only when upstream has no build system usable in BuildStream, or a bootstrap
compiler is genuinely required. **It weakens the provenance claim, so it needs a stated
reason in the element.**

```yaml
kind: manual

variables:
  version: '1.2.3'
  strip-binaries: ""   # required — release binaries are already stripped
  (?):
  - arch == "x86_64":
      arch-tag: "amd64"
  - arch == "aarch64":
      arch-tag: "arm64"

sources:
- kind: tar
  url: github:owner/project/releases/download/v%{version}/project-linux-%{arch-tag}.tar.gz
  ref: <sha256>

install-commands:
- install -Dm755 project "%{install-root}%{bindir}/project"
- '%{install-extra}'
```

Two traps: `strip-binaries: ""` is **required** for already-stripped or non-ELF
payloads (the symptom otherwise is `freedesktop-sdk-stripper` exiting `127`), and
source URLs do not expand arbitrary variables — the host part must be an alias from
`include/aliases.yml`.

## Checklist

- [ ] Confirmed FSDK has no component for this tool
- [ ] Confirmed upstream ships no maintained distroless image
- [ ] Every dependency is vendored in `sources:` — no network at build time
- [ ] Go: `GOROOT: "%{libdir}/go"` is set
- [ ] Go: `GOFLAGS="-mod=vendor"` is exported
- [ ] Rust: the `cargo2` block is generated, not hand-edited
- [ ] Binaries install to `%{bindir}`, prefixed with `%{install-root}`
- [ ] `strip-binaries: ""` set if and only if the payload is non-ELF or pre-stripped
- [ ] No `/dev/stdin` heredoc redirection (fails on the grid)
- [ ] `just validate` resolves; `just verify` passes for the consuming image

## Common Rationalizations

| Rationalization | Reality |
|---|---|
| "Dakota prefers pre-built binaries, so I will too." | Dakota ships an OS. Here, provenance is the product — #115 makes source the default. |
| "It's Go, it can just download its modules." | Not in a network-isolated sandbox. |
| "One vendoring strategy fits all Go projects." | Pick the smaller maintenance burden. `go_module` refs update in place; tarballs do not. |
| "I'll hand-tweak one line of the cargo2 block." | It is generated. Regenerate it. |
| "It built locally, so the sandbox is fine." | Local builds are not the grid. Check `GOROOT` and `/dev/stdin`. |

## Red Flags

- any network-dependent build step
- a pre-built binary chosen without a written justification
- a hand-edited `cargo2` block
- missing `GOROOT` in an element that runs `go build`
- installing outside `/usr`, or without `%{install-root}`
