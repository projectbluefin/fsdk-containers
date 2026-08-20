kind: stack
description: |
  Go toolchain (build-time image) dependencies, built on the base stack.

  FSDK's components/go.bst ships the full upstream Go distribution
  (go1.26.5 at the pinned junction ref) installed with GOROOT at
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
