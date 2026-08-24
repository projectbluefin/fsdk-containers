kind: stack
description: |
  Nginx runtime stack: base distroless runtime (glibc, CA certs, tzdata)
  plus the source-built nginx binary and its linked libraries
  (pcre2, openssl, zlib).

  Wave 0 feasibility spike (#146): INERT — no OCI element, no
  targets.json entry, nothing published. Resolves and builds on the
  ghost BuildBarn grid (`just bst build elements/nginx/nginx-stack.bst`,
  remote execution default) — verified 2026-08-20. The full
  four-question spike record (mechanism / dependency set / resolution /
  upstream ref) lives in nginx/nginx.bst.
depends:
  - base/base-stack.bst
  - nginx/nginx.bst
