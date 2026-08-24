kind: stack
description: |
  curl runtime dependencies (built on base stack) — Wave 0 feasibility
  spike for #146. Inert by design: no OCI element, no targets.json entry,
  nothing published. There is deliberately no curl/curl.bst build element:
  curl's mechanism is "FSDK component exists", so the spike IS this stack
  (same shape as go, which also has no go.bst).

  Four answers, measured (not assumed):

  1. MECHANISM: FSDK component. freedesktop-sdk.bst:components/curl.bst is
     an FSDK `kind: cmake` element that builds upstream curl from source;
     we compose it (hard rule: don't duplicate upstream). #113's table
     entry for curl ("FSDK component exists — trivial, depends: and done")
     is CONFIRMED CORRECT — no mechanism correction needed.

  2. DEPENDENCY SET (direct): base/base-stack.bst +
     freedesktop-sdk.bst:components/curl.bst. FSDK curl.bst's own
     `depends:` adds components/libnghttp2, libnghttp3, libngtcp2, libpsl,
     openssl, zlib, zstd over public-stacks/runtime-minimal, plus
     `runtime-depends:` components/ca-certificates (already in base-stack).
     Transitive closure (`bst show --deps run`): libidn2 + libunistring
     via libpsl; gnutls, nettle, gmp, libtasn1, p11-kit, libffi via
     libngtcp2's TLS; everything else (glibc, gcc-libs, zlib-ng, tzdata,
     os-release) already lands via base-stack.

  3. RESOLVES: yes — `just validate` / `bst show` clean, and the stack
     BUILDS on the ghost BuildBarn grid (`just bst build
     curl/curl-stack.bst`), not merely resolves.

  4. UPSTREAM VERSION + REF: curl 8.21.0, FSDK ref
     curl-8_21_0-0-g68720b4837284335b2d63cb358f8f6ce65f5bc55 at the pinned
     junction ref freedesktop-sdk-26.08rc.1-0-ge076d4978ee6945763486f6ebd755d189460e4e7.
     Verified against upstream: github.com/curl/curl tag curl-8_21_0
     dereferences to commit 68720b4837284335b2d63cb358f8f6ce65f5bc55
     (`git ls-remote https://github.com/curl/curl.git refs/tags/curl-8_21_0^{}`).

depends:
  - base/base-stack.bst
  - freedesktop-sdk.bst:components/curl.bst
