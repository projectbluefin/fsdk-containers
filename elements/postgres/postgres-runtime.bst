kind: compose
description: |
  Chisel the postgres stack down to runtime-only, distroless.

  The exclude list chisels the FSDK junction artifacts (openssl/icu/
  libxml2/etc. carry FSDK split-rule domains). postgres/postgres.bst's own
  payload is all `runtime` domain (fsdk-containers has no project-level
  split-rules), so its devel/doc/build-tooling payload is pruned in
  postgres.bst's install-commands instead — see the comment there.

build-depends:
  - postgres/postgres-stack.bst

config:
  exclude:
    - debug
    - devel
    - doc
    - locale
    - static-blocklist
    - vm-only
    - tests
    # NOTE: 'shells' covers only /usr/share/fish and /usr/share/zsh data
    # dirs. The bash binary lives in the runtime domain and is removed by
    # the SLIM recipe at the OCI stage (include/slim.yml), not here.
    - shells
