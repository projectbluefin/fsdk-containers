kind: stack
description: |
  Go toolchain (build-time image) dependencies, built on the base stack.

  Wave 0 feasibility record (issue #146):
  1. Mechanism: FSDK COMPONENT — freedesktop-sdk.bst:components/go.bst
     builds the full upstream Go distribution from golang/go.git with
     FSDK's patch queue. No tarball element, no go_module source, no JVM.
     #113's mechanism table already had this right ("FSDK component
     exists: curl, go"); the Wave 0 brief's tarball fallback was not
     needed. There is deliberately NO elements/go/go.bst: a manual
     element would duplicate the FSDK component and forfeit its CVE
     patching (same pattern as curl, the other FSDK-component target).
     go_module (#144, enabled in project.conf) is for building Go
     *applications* from source, not the toolchain itself.
  2. Dependency set: base/base-stack.bst + components/go.bst +
     components/gcc.bst (gcc rationale below). Nothing else: go.bst's
     only runtime dep is runtime-minimal, already in base-stack.
  3. Resolves: yes. Built on the ghost BuildBarn grid in PR #147, and
     re-verified 2026-08-20 at junction
     freedesktop-sdk-26.08rc.1-0-ge076d4978ee6945763486f6ebd755d189460e4e7
     (`just bst build go/go-stack.bst`, artifact key be5b1d8e, 289-element
     pipeline, 0 failed).
  4. Upstream version + ref: go1.26.6, git-describe
     go1.26.6-0-g1ea5a71ad8ceb7b9f16b4b6f8ea4739a4327dd6e — verifiable in
     FSDK's elements/include/go-source.yml at the pinned junction ref in
     elements/freedesktop-sdk.bst. (This comment claimed go1.26.5 until
     the 26.08rc.1 rebase; trust go-source.yml at the junction ref over
     any version quoted here.)

  FSDK's components/go.bst ships the full upstream Go distribution
  (version/ref: the Wave 0 record above) installed with GOROOT at
  %{libdir}/go. FSDK's libdir is the MULTIARCH TRIPLET dir:
  /usr/lib/x86_64-linux-gnu/go on x86_64, /usr/lib/aarch64-linux-gnu/go
  on aarch64 (verified via `bst artifact list-contents`). Anything
  referencing GOROOT (Env vars, prune globs, smoke tests) must use the
  /usr/lib/*/go glob or %{libdir}/go — never a bare /usr/lib/go.
  Layout: bin/, pkg/tool, pkg/include, src/, api/, misc/, test/, plus
  symlinks from %{bindir} (/usr/bin/go, gofmt).
  Its only runtime dep is runtime-minimal, already in base-stack.

  gcc is included because this is a *toolchain* image: FSDK builds Go
  with CGO_ENABLED=1, and a usable `go build` for any package that does
  `import "C"` (or defaults to cgo for net/os/user resolution) needs a C
  compiler, headers, and crt objects. The upstream golang:* image (276 MB)
  also ships gcc; dropping it silently changes produced binaries.
  Pure-Go (CGO_ENABLED=0) consumers work without it — if the gcc payload
  proves too expensive at Wave 4 measurement time, it can be split into a
  `go` (pure) / `go-cgo` pair; start with the complete toolchain.

  NOT included, deliberately: git (`go mod download` works over HTTPS via
  the module proxy; git is only needed for direct-VCS/private modules —
  revisit at Wave 4) and any shell (see go-runtime.bst notes).

depends:
  - base/base-stack.bst
  - freedesktop-sdk.bst:components/go.bst
  - freedesktop-sdk.bst:components/gcc.bst
