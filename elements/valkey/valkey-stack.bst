kind: stack
description: Valkey server runtime dependencies (built on base stack)

# Wave 0 spike (issue #146): INERT deliverable — stack + component only, no OCI
# element, no targets.json entry. The four spike answers (mechanism: tarball +
# manual build, FSDK has no valkey/redis component; dependency set; resolves;
# upstream 9.1.1 + pinned sha256) are recorded in valkey/valkey.bst. This exact
# graph built green on the ghost BuildBarn grid 2026-08-21
# (`just bst build valkey/valkey-stack.bst`, 0 failures).
#
# valkey-server links its vendored deps (jemalloc, libvalkey, lua) statically,
# so glibc from the base stack is the only runtime requirement.
depends:
  - base/base-stack.bst
  - valkey/valkey.bst
