kind: compose
description: |
  Chisel the go stack for the toolchain image.

  CRITICAL DIFFERENCE from base/python: the `devel` domain is KEPT, not
  excluded. Two FSDK split-rule extensions make the standard exclude list
  fatal to a working toolchain:

  1. components/go.bst adds %{libdir}/go/src/** to `devel`. Since Go 1.20
     the distribution ships no precompiled stdlib archives — `go build`
     compiles the standard library from $GOROOT/src on demand. Excluding
     devel strips the stdlib source and every `go build` fails.
  2. components/gcc.bst places its entire compiler payload in `devel`:
     %{bindir}/*, %{libexecdir}/** (cc1, collect2), %{libdir}/gcc/**,
     crt objects and .a files. cgo needs all of it. glibc headers
     (%{includedir}, devel domain by default rule) are likewise required.

  Keeping devel also keeps pkgconfig/aclocal/cmake metadata and other
  static libs — acceptable for a build-time image; the Wave 4 OCI stage
  can prune surgically (like python's stdlib prune) but must never remove
  %{libdir}/go/src, %{libdir}/go/pkg, or the gcc tree. Note %{libdir} is
  the multiarch triplet dir (/usr/lib/x86_64-linux-gnu etc.) — prune
  globs must match /usr/lib/*/go.

  Verified on the BuildBarn grid (Wave 0): composed artifact contains the
  complete GOROOT (16,646 files: bin/go, pkg/tool/linux_amd64/compile,
  12,799 stdlib src files, api/, test/), gcc + binutils + libexec/gcc
  + /usr/include, and zero doc/locale/installed-tests files. Residue:
  ~9 debug files survive under /usr/lib/debug (ld-linux .debug, dwz dir)
  because they are orphans of their own elements' debug domain — the OCI
  stage should `rm -rf /layer/usr/lib/debug`. `go/test` (Go's own test
  suite, runtime domain — FSDK's `tests` rule only matches
  installed-tests) is a size-prune candidate, as are `go/misc`.

build-depends:
  - go/go-stack.bst

config:
  exclude:
    - debug
    - doc
    - locale
    - static-blocklist
    - vm-only
    - tests
    - shells
