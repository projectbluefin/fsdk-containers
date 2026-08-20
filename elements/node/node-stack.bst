kind: stack
description: |
  Node.js runtime stack: base essentials (glibc, CA certs, tzdata) plus the
  node binary and the FSDK shared libraries it links against (openssl,
  zlib, c-ares, nghttp2, brotli, icu — pulled in via node.bst's runtime
  depends).

depends:
  - base/base-stack.bst
  - node/node.bst
