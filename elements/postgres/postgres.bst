kind: manual
description: |
  Build PostgreSQL from the upstream source tarball (tarball source build;
  FSDK has no components/postgresql.bst). Pattern mirrors
  elements/lab-runner/nginx.bst: declare every build-time utility the
  upstream build shells out to, because the FSDK build sandbox has no
  ambient userland.

  DISTROLESS FEASIBILITY VERDICT (Wave 0 spike): postgres CAN be distroless.
  initdb, postgres, pg_ctl are plain ELF binaries; none of initdb, the
  postmaster, or the bootstrap backend needs a shell. What does NOT survive
  distroless is the official image's docker-entrypoint.sh (shell script that
  initdbs, su-execs, and edits config) and `pg_ctl start` (pg_ctl always
  spawns the postmaster via system(3) -> /bin/sh). The container contract
  therefore is:

    * Entrypoint is `/usr/bin/postgres -D /var/lib/postgresql/data`
      (postgres handles SIGTERM/SIGINT/SIGQUIT correctly as PID 1).
    * PGDATA must be initialized out-of-band: a one-shot Job or init step
      running `/usr/bin/initdb -D /var/lib/postgresql/data -E UTF8
      --locale=C.UTF-8` (initdb is not idempotent; has no --if-exists).
      A Wave 4 option is a tiny compiled entrypoint shim (Go/static C) that
      does initdb-if-empty + exec postgres to recover the official image's
      docker-run UX.
    * Non-root is MANDATORY, not optional: the postmaster refuses euid 0
      ("root execution of the PostgreSQL server is not permitted") and
      initdb requires getpwuid(geteuid()) to resolve, so the image must
      ship an /etc/passwd entry for UID 65532 (#120 contract) — append it
      in the Wave 4 oci element; the base layer ships a root-only passwd
      (FSDK integration/extra-fs.bst).
    * Locale: the slim recipe deletes /usr/lib/locale/locale-archive, so
      glibc locales are limited to C/POSIX and the compiled-in C.UTF-8
      (glibc >= 2.35) — C.UTF-8 needs no locale-archive, so set
      LANG=C.UTF-8 and initdb with --locale=C.UTF-8. ICU is linked
      (--with-icu) so per-database ICU collations are available and
      indexes are insulated from glibc collation changes across FSDK bumps;
      costs ~30 MB of libicudata and is worth it for a database.

sources:
  - kind: tar
    url: https://ftp.postgresql.org/pub/source/v%{postgres_version}/postgresql-%{postgres_version}.tar.bz2
    # sha256 of postgresql-18.4.tar.bz2, verified against the upstream
    # sidecar postgresql-18.4.tar.bz2.sha256 (postgresql.org publishes one
    # per release) and by independent local download. Bump manually: update
    # postgres_version and ref together, verifying the new sidecar.
    ref: 81a81ec695fb0c7901407defaa1d2f7973617154cf27ba74e3a7ab8e64436094

build-depends:
  # Sandbox base: shell + linker/runtime pieces the configure scripts need.
  - freedesktop-sdk.bst:public-stacks/runtime-gnu.bst
  - freedesktop-sdk.bst:components/gcc.bst
  - freedesktop-sdk.bst:components/make.bst
  # configure and the generated Makefiles shell out to sed/grep/awk without
  # checking for them; declare every tool the build runs (nginx.bst
  # precedent).
  - freedesktop-sdk.bst:components/sed.bst
  - freedesktop-sdk.bst:components/grep.bst
  - freedesktop-sdk.bst:components/gawk.bst
  - freedesktop-sdk.bst:bootstrap/coreutils.bst
  # PostgreSQL docs (install-requirements): "Perl 5.14 or later is needed
  # during the build process" even without --with-perl.
  - freedesktop-sdk.bst:components/perl.bst
  # configure detects openssl/icu/libxml2 via pkg-config.
  - freedesktop-sdk.bst:components/pkg-config.bst
  # gram.c/scan.c ship pregenerated in the release tarball, but bison/flex
  # are staged defensively: if a timestamp skew ever triggers regeneration,
  # the build fails obscurely without them.
  - freedesktop-sdk.bst:components/bison.bst
  - freedesktop-sdk.bst:components/flex.bst
  # Link-time dependencies (headers + libs staged in the sandbox).
  - freedesktop-sdk.bst:components/openssl.bst
  - freedesktop-sdk.bst:components/zlib.bst
  - freedesktop-sdk.bst:components/lz4.bst
  - freedesktop-sdk.bst:components/zstd.bst
  - freedesktop-sdk.bst:components/icu.bst
  - freedesktop-sdk.bst:components/libxml2.bst
  # configure records the --with-system-tzdata path; stage tzdata so the
  # directory exists in the sandbox.
  - freedesktop-sdk.bst:components/tzdata.bst

# Runtime linkage of the built binaries (qemu-img.bst precedent: manual
# elements declare their own runtime depends).
depends:
  - freedesktop-sdk.bst:components/openssl.bst
  - freedesktop-sdk.bst:components/zlib.bst
  - freedesktop-sdk.bst:components/lz4.bst
  - freedesktop-sdk.bst:components/zstd.bst
  - freedesktop-sdk.bst:components/icu.bst
  - freedesktop-sdk.bst:components/libxml2.bst
  # tzdata itself comes via base/base-stack.bst (postgres is configured with
  # --with-system-tzdata=/usr/share/zoneinfo and reads the OS tz database).

variables:
  # freedesktop-sdk-stripper exits 127 in the minimal manual workspace;
  # pruning/squash happens in the later OCI stage (add-new-image.md).
  strip-binaries: ""
  postgres_version: "18.4"
  hardening-flags: ""
  (?):
    - arch == "x86_64":
        hardening-flags: "-fstack-protector-strong -fstack-clash-protection -D_FORTIFY_SOURCE=3 -fcf-protection=full"
    - arch == "aarch64":
        hardening-flags: "-fstack-protector-strong -fstack-clash-protection -D_FORTIFY_SOURCE=3 -mbranch-protection=standard"

config:
  configure-commands:
    # Everything upstream installs lands under /usr/bin, /usr/lib and
    # /usr/share/postgresql, so there is no merged-usr /usr/sbin hazard
    # (nginx.bst precedent). FSDK has no components/readline.bst (only
    # bootstrap/readline.bst) and a distroless server image has no
    # interactive psql, so readline/libedit line editing is dropped with
    # --without-readline. --disable-nls drops gettext .mo files. No
    # contrib/ (uuid-ossp needs libuuid, xml2 needs libxslt, pg_stat_
    # statements is contrib) — revisit as a deliberate addition, not a
    # default. ICU/zlib/lz4/zstd/libxml2/openssl are the deliberate set.
    - |
      CFLAGS="-O2 %{hardening-flags}" ./configure \
        --prefix=/usr \
        --libdir=/usr/lib \
        --sysconfdir=/etc/postgresql \
        --with-ssl=openssl \
        --with-icu \
        --with-zlib \
        --with-lz4 \
        --with-zstd \
        --with-libxml \
        --without-readline \
        --disable-nls \
        --with-system-tzdata=/usr/share/zoneinfo

  build-commands:
    - make -j%{max-jobs}

  install-commands:
    - make install DESTDIR="%{install-root}"
    # Prune build-only payload here: fsdk-containers' project.conf defines
    # no split-rules of its own, so this manual element's whole artifact is
    # the `runtime` domain and the compose `exclude: [devel, doc, ...]`
    # only chisels the FSDK junction artifacts. Devel headers, man/html
    # docs, pgxs extension-build makefiles, static archives and pkg-config
    # files must therefore be removed by hand.
    - rm -rf "%{install-root}/usr/include"
    - rm -rf "%{install-root}/usr/share/doc" "%{install-root}/usr/share/man"
    - rm -rf "%{install-root}/usr/lib/postgresql/pgxs"
    - rm -rf "%{install-root}/usr/lib/pkgconfig"
    - rm -f "%{install-root}/usr/lib/"*.a "%{install-root}/usr/bin/pg_config"
    # ecpg is the embedded-SQL precompiler + its client libraries: build
    # tooling for ECPG applications, not needed to run the server.
    - rm -f "%{install-root}/usr/bin/ecpg" "%{install-root}/usr/lib/libecpg"* "%{install-root}/usr/lib/libpgtypes"*
    # PGDATA scaffold (#120 non-root contract). Only the mkdir survives the
    # BuildBarn remote-execution grid: REAPI action outputs do not record
    # uid/gid and normalize directory modes, so chmod 0700 / chown 65532
    # here are silently lost (verified: checked-out artifact shows
    # 0755 root-ish). Ownership and mode must be (re)applied in the OCI
    # script stage, which runs in-sandbox when build-oci materializes the
    # layer tar: chmod 0700 + chown 65532:65532 /layer/var/lib/postgresql/data
    # there. A runtime volume mount still needs matching fsGroup or a chown
    # at provision time.
    - mkdir -p "%{install-root}/var/lib/postgresql/data"
