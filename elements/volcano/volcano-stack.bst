kind: stack
description: |
  Volcano runtime stack: the statically linked (CGO_ENABLED=0)
  control-plane binaries on the shared base stack (glibc, ca-certs,
  tzdata). ca-certificates are required: all three binaries talk to the
  Kubernetes API over TLS, and vc-webhook-manager serves TLS.

depends:
  - base/base-stack.bst
  - volcano/volcano.bst
