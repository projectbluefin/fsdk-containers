kind: stack
description: |
  Nginx runtime stack: base distroless runtime (glibc, CA certs, tzdata)
  plus the source-built nginx binary and its linked libraries
  (pcre2, openssl, zlib).
depends:
  - base/base-stack.bst
  - nginx/nginx.bst
