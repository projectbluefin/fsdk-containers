kind: stack
description: |
  Node.js runtime stack: base essentials (glibc, CA certs, tzdata) plus the
  node binary and the FSDK shared libraries it links against (openssl,
  zlib, c-ares, nghttp2, brotli, icu — pulled in via node.bst's runtime
  depends).

# ── Wave 0 spike verdict (issue #146) — INERT: no OCI element, no
#    targets.json entry, nothing published. See node.bst for full notes.
#
# 1. MECHANISM: upstream nodejs.org source tarball, built with `kind: manual`
#    (gyp → ninja, make driver). CORRECTS #113/#146's assumption that node is
#    a `go_module` target — it is a C++/V8 build. The FSDK junction was
#    checked first (junction ref e076d497 / 26.08rc.1): it ships NO
#    components/node.bst or nodejs.bst, so there is nothing to compose.
#    The prebuilt nodejs.org *binary* tarball was rejected for the same
#    reason as every binary here: it links RHEL-family system libs, not
#    FSDK's — building from source against FSDK's CVE-patched
#    openssl/zlib/c-ares/nghttp2/brotli/icu is what makes the image
#    inherit FSDK's patching.
# 2. DEPENDENCY SET (runtime, all via node.bst `depends:`): FSDK
#    components openssl, zlib, c-ares, libnghttp2, brotli, icu, plus
#    base-stack (glibc, CA certs, tzdata). libuv/llhttp/ada/simdjson stay
#    bundled — FSDK ships no components for them. Build-only deps
#    (gcc, make, ninja, python3, pkg-config, sed/grep/gawk, coreutils,
#    binutils/strip) never leak into the runtime closure.
# 3. RESOLVES: yes — `just bst show node/node-stack.bst` renders the full
#    graph; `just bst build node/node-stack.bst` succeeds on the ghost
#    BuildBarn grid (see PR for run evidence).
# 4. UPSTREAM VERSION + REF: Node.js v24.19.0 (24.x active LTS "Krypton"),
#    nodejs.org dist tarball, sha256
#    16fe258006a6e86844fbe05b3b5e1e5623ca8d3da54e32d98d9e83234bf25b01 —
#    verified 2026-08-20 against
#    https://nodejs.org/dist/v24.19.0/SHASUMS256.txt.

depends:
  - base/base-stack.bst
  - node/node.bst
