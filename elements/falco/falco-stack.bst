kind: stack
description: |
  Falco runtime stack — Wave 0 feasibility spike for issue #146. INERT: no
  OCI element, no targets.json entry, nothing published.

  The four answers (full evidence in falco/falco.bst):
    1. Mechanism: upstream binary tarball (download.falco.org) — the same
       artifact upstream's own image (`falcosecurity/falco`, wolfi-base +
       apk + curl/jq — NOT distroless by this repo's no-shell definition,
       so hard rule 3 does not apply) is built from. Mechanism correction
       vs #113: NOT go_module, NOT FSDK component, and the from-source
       CMake path (~10 new dep elements + a container-plugin patch; draft
       in git history, PR #147) is unjustified at Wave 0 cost.
       Caveat: the tarball statically bundles openssl/curl/gRPC etc., which
       therefore do NOT inherit FSDK CVE patching — security fixes track
       upstream falco releases.
    2. Dependency set: glibc only (all heavy deps statically linked
       upstream); provided here by base-stack.
    3. Resolves and builds on the BuildBarn grid:
       `just bst build falco/falco-stack.bst` — PASSED 2026-08-20
       (x86_64), including the in-sandbox `falco --version` smoke test.
    4. Upstream: falco 0.44.1 (2026-06-11), tarball sha256 pinned in
       falco/falco.bst (verified live 2026-08-20; no upstream sidecar
       checksums exist).

  Runtime contract for the future OCI element (from upstream's LABEL usage):
  --privileged + /host mounts (/proc, /etc, CRI socket); runs as root —
  falco is an inherently privileged eBPF sensor, an intentional exception to
  the #120 non-root contract. Modern-eBPF-only: no kmod, no shell, no
  runtime downloads; entrypoint is /usr/bin/falco directly.

depends:
  - base/base-stack.bst
  - falco/falco.bst
