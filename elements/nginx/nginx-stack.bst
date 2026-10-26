kind: stack
description: |
  Nginx runtime stack: base distroless runtime (glibc, CA certs, tzdata)
  plus the source-built nginx binary and its linked libraries
  (pcre2, openssl, zlib).

  Wave 0 feasibility spike (#146): INERT — no OCI element, no
  targets.json entry, nothing published. Resolved and built on the
  now-retired BuildBarn grid (`just bst build elements/nginx/nginx-stack.bst`,
  then defaulting to remote execution) — verified 2026-08-20; the current
  model builds locally in the bst2 container. The full
  four-question spike record (mechanism / dependency set / resolution /
  upstream ref) lives in nginx/nginx.bst.
depends:
  - base/base-stack.bst
  - nginx/nginx.bst
