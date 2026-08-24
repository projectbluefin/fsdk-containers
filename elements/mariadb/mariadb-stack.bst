kind: stack
description: |
  MariaDB server runtime dependencies (built on base stack)

  Wave 0 feasibility spike (issue #146) — the four questions:

  1. Mechanism: TARBALL source build (CMake + Ninja via kind: manual).
     FSDK has no components/mariadb.bst (checked the junction), so the
     official mariadb.org source tarball is built directly, following the
     elements/lab-runner/nginx.bst precedent. This MATCHES #113's
     mechanism table (batch B, tarball) — no correction needed.
  2. Dependency set (exact): see mariadb/mariadb.bst — build-depends:
     runtime-gnu, gcc, cmake, ninja, bison, fmtlib (headers; bundled
     libfmt would download at build time), sed, grep, gawk, coreutils,
     pkg-config; depends: openssl, zlib, pcre2 (bootstrap; bundled pcre2
     would download at build time), ncurses (bootstrap; client line
     editing), libaio + liburing (InnoDB async I/O), lz4 + lzo (InnoDB
     page-compression providers). Runtime closure here adds only
     base-stack (glibc/libstdc++, CA certs, tzdata).
  3. Resolves: yes — `just validate` and `bst build` both resolve the
     graph. Built on the ghost BuildBarn grid (remote execution) on
     2026-08-21: `bst build mariadb/mariadb-stack.bst` green (ninja
     [1320/1320], full remote log), and the composed mariadb-runtime.bst
     smoke-tested: `mariadbd --version` runs against only the compose
     artifact's own libs → runtime closure is complete. The first grid
     run caught one real bug: MariaDB's install tree has no etc/, so the
     my.cnf heredoc needed `mkdir -p .../etc` (fixed in mariadb.bst).
     (The grid needed a control-plane restart mid-session — wedged
     scheduler/frontend/storage silently parked every client's
     "Uploading input root"; rollout restart of scheduler, frontend and
     storage unblocked all six concurrent Wave 0 builds. Recorded in
     docs/skills/remote-execution.md.)
  4. Upstream: MariaDB 11.8.8. 11.8 is an LTS line but not the newest:
     12.3 is upstream's current Stable/LTS series (EOL 2029-06-12). The
     11.8 pin was the version verified at #147 spike time; renovate owns
     the version from here (12.x bump already queued as PR #185), and
     11.8.9 shipped 2026-08-22, so the pin lags its own series head.
     https://archive.mariadb.org/mariadb-11.8.8/source/mariadb-11.8.8.tar.gz
     sha256 bd023a4959faf012db7f0ebfc0d276729e67e5443df193163f98d80fdfc524c9
     — cross-verified against the official download REST API
     (downloads.mariadb.org/rest-api/mariadb/11.8.8/). Renovate tracks
     MariaDB/server github-tags in mariadb.bst.

  mariadb.bst declares its linked libraries (openssl, zlib, pcre2,
  ncurses, libaio, liburing, lz4, lzo) as `depends:`, so their runtime
  domains flow in transitively; base-stack supplies glibc/libstdc++,
  CA certs and tzdata.
depends:
  - base/base-stack.bst
  - mariadb/mariadb.bst
