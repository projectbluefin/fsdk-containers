kind: stack
description: Valkey server runtime dependencies (built on base stack)

# valkey-server links its vendored deps (jemalloc, libvalkey, lua) statically,
# so glibc from the base stack is the only runtime requirement.
depends:
  - base/base-stack.bst
  - valkey/valkey.bst
