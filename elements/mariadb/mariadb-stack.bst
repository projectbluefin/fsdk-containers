kind: stack
description: MariaDB server runtime dependencies (built on base stack)

# mariadb.bst declares its linked libraries (openssl, zlib, pcre2, ncurses,
# libaio, liburing, lz4, lzo) as `depends:`, so their runtime domains flow
# in transitively; base-stack supplies glibc/libstdc++, CA certs and tzdata.
depends:
  - base/base-stack.bst
  - mariadb/mariadb.bst
