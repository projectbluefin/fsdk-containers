kind: manual
description: |
  Build MariaDB server (mysqld) + client tools from the official source
  tarball for the distroless mariadb image.

  Mechanism: tarball source build (no FSDK components/mariadb.bst exists),
  following the elements/lab-runner/nginx.bst precedent.

  Merged-usr: FSDK's sysroot has /usr/sbin as a symlink to /usr/bin, so the
  RPM/DEB layouts (INSTALL_SBINDIR=sbin) cannot be staged. INSTALL_LAYOUT is
  STANDALONE (whose INSTALL_SBINDIR defaults to bin) and SBINDIR is pinned
  explicitly so a future layout default change cannot silently move mysqld
  into sbin.

  Distroless init story: the official image's shell entrypoint runs
  mariadb-install-db on first start. That script only concatenates the
  bootstrap SQL in share/mysql (mariadb_system_tables{,_data}.sql,
  mariadb_performance_tables.sql, fill_help_tables.sql, mariadb_sys_schema.sql,
  maria_add_gis_sp_bootstrap.sql) and pipes it into `mysqld --bootstrap` —
  a pure binary invocation. Those SQL files ARE shipped in this element
  (share/mysql), so a shell-free init (static Go entrypoint, or a k8s
  initContainer/exec probe driver) can replicate it. The shell scripts
  themselves (scripts/, support-files/) are pruned: they are unrunnable
  dead weight in a no-shell image.

  mariabackup is OFF for the Wave 0 spike: it recompiles InnoDB with
  different defines (~20% of build time). mariadb-dump (logical backup)
  still ships. Revisit -DWITH_MARIABACKUP=ON if the image needs physical
  backups (e.g. mariadb-operator integration).

sources:
  - kind: tar
    url: https://archive.mariadb.org/mariadb-%{mariadb_version}/source/mariadb-%{mariadb_version}.tar.gz
    # sha256 verified against the official MariaDB download REST API
    # (downloads.mariadb.org/rest-api/mariadb/11.8.8/, file mariadb-11.8.8.tar.gz)
    ref: bd023a4959faf012db7f0ebfc0d276729e67e5443df193163f98d80fdfc524c9

build-depends:
  - freedesktop-sdk.bst:public-stacks/runtime-gnu.bst
  - freedesktop-sdk.bst:components/gcc.bst
  - freedesktop-sdk.bst:components/cmake.bst
  - freedesktop-sdk.bst:components/ninja.bst
  # sql_yacc.yy / sql_lex.cc parser generation — hard requirement, no fallback.
  - freedesktop-sdk.bst:components/bison.bst
  # WITH_LIBFMT=system: the bundled path (cmake/libfmt.cmake BUNDLE_LIBFMT)
  # is an ExternalProject that downloads fmt-12.1.0.zip at BUILD time,
  # which the network-less sandbox cannot do. FSDK's fmtlib is header-usable
  # (MariaDB's CHECK_CXX_SOURCE_RUNS probes FMT_HEADER_ONLY mode), so this
  # adds headers only — no runtime library dep.
  - freedesktop-sdk.bst:components/fmtlib.bst
  # CMake's configure checks, the generated Ninja rules and scripts/ CMake
  # (CAT_EXECUTABLE etc.) shell out to sed/grep/awk/coreutils/pkg-config
  # without checking; FSDK's sandbox has no ambient userland, so declare
  # every tool (elements/lab-runner/nginx.bst precedent).
  - freedesktop-sdk.bst:components/sed.bst
  - freedesktop-sdk.bst:components/grep.bst
  - freedesktop-sdk.bst:components/gawk.bst
  - freedesktop-sdk.bst:bootstrap/coreutils.bst
  - freedesktop-sdk.bst:components/pkg-config.bst

# Runtime-linked libraries. `depends:` (not build-depends:) so the runtime
# artifacts propagate into mariadb-stack.bst — same pattern as FSDK's own
# components/curl.bst.
depends:
  # WITH_SSL=system: TLS for client connections + sha256_password caching;
  # keeps TLS CVE inheritance on FSDK's openssl instead of the bundled wolfssl.
  - freedesktop-sdk.bst:components/openssl.bst
  # WITH_ZLIB=system: InnoDB built-in page compression + protocol compression.
  - freedesktop-sdk.bst:components/zlib.bst
  # WITH_PCRE=system is MANDATORY here: WITH_PCRE=bundled does an
  # ExternalProject download of pcre2-10.47.zip at build time (cmake/pcre.cmake),
  # which the network-less sandbox cannot do. FSDK bootstrap pins exactly
  # pcre2 10.47, the version upstream would have fetched. Used for REGEXP.
  - freedesktop-sdk.bst:bootstrap/pcre2.bst
  # Client line editing/history (FIND_CURSES in cmake/readline.cmake).
  # ncurses exists only under bootstrap/ in FSDK.
  - freedesktop-sdk.bst:bootstrap/ncurses.bst
  # InnoDB native Linux AIO (FindLIBAIO.cmake); without it InnoDB silently
  # falls back to simulated AIO (slower under concurrency).
  - freedesktop-sdk.bst:components/libaio.bst
  # InnoDB io_uring backend (FindURING.cmake).
  - freedesktop-sdk.bst:components/liburing.bst
  # provider_lz4 / provider_lzo plugins (InnoDB page compression providers).
  - freedesktop-sdk.bst:components/lz4.bst
  - freedesktop-sdk.bst:components/lzo.bst

variables:
  strip-binaries: ""
  # renovate: datasource=github-tags depName=MariaDB/server extractVersion=^mariadb-(?<version>.+)$
  mariadb_version: 11.8.8
  hardening-flags: ""
  (?):
    - arch == "x86_64":
        hardening-flags: "-fstack-protector-strong -fstack-clash-protection -D_FORTIFY_SOURCE=3 -fcf-protection=full"
    - arch == "aarch64":
        hardening-flags: "-fstack-protector-strong -fstack-clash-protection -D_FORTIFY_SOURCE=3 -mbranch-protection=standard"

config:
  configure-commands:
    # Empty INSTALL_MYSQLTESTDIR / INSTALL_SQLBENCHDIR are load-bearing:
    # the install rules are guarded by IF(<var>) (cmake/install_macros.cmake
    # INSTALL_MYSQL_TEST, sql-bench/CMakeLists.txt early RETURN), so empty
    # skips the ~600MB mariadb-test suite and the perl sql-bench suite
    # instead of installing-then-deleting them.
    #
    # INSTALL_SUPPORTFILESDIR is deliberately NOT empty: in
    # support-files/CMakeLists.txt only the magic/policy installs are
    # guarded by IF(INSTALL_SUPPORTFILESDIR); the mysqld_multi/logrotate/
    # binary-configure/mini-benchmark loop (line ~75) and mysql.server
    # (line ~136) use ${inst_location} (= INSTALL_SUPPORTFILESDIR)
    # UNGUARDED, so an empty value is a hard configure error
    # ("INSTALL PROGRAMS given no DESTINATION!"). Install to a sacrificial
    # dir and rm -rf it in install-commands instead.
    # PLUGIN_*=NO: engines/auth/plugins nobody runs in a slim container —
    # RocksDB/Mroonga/Spider/OQGraph/ColumnStore are each huge compiles
    # (OQGraph also needs boost+judy, absent from FSDK); CONNECT needs
    # libxml2; S3/aws_key_management/hashicorp need curl; auth_pam/auth_
    # gssapi need PAM/krb5; feedback is telemetry; snappy/bzip2/lzma
    # compression providers need libs we don't carry (lz4/lzo kept).
    - |
      cmake -S . -B build -G Ninja \
        -DCMAKE_BUILD_TYPE=RelWithDebInfo \
        -DCMAKE_INSTALL_PREFIX=/usr \
        -DINSTALL_LAYOUT=STANDALONE \
        -DINSTALL_SBINDIR=bin \
        -DINSTALL_MYSQLSHAREDIR=share/mysql \
        -DINSTALL_PLUGINDIR=lib/mariadb/plugin \
        -DINSTALL_MYSQLDATADIR=/var/lib/mysql \
        -DINSTALL_UNIX_ADDRDIR=/run/mysqld/mysqld.sock \
        -DINSTALL_DOCDIR=share/doc/mariadb \
        -DINSTALL_DOCREADMEDIR=share/doc/mariadb \
        -DINSTALL_INFODIR=share/info \
        -DINSTALL_MYSQLTESTDIR= \
        -DINSTALL_SQLBENCHDIR= \
        -DINSTALL_SUPPORTFILESDIR=share/mariadb-support \
        -DWITH_SSL=system \
        -DWITH_ZLIB=system \
        -DWITH_PCRE=system \
        -DWITH_LIBFMT=system \
        -DWITH_JEMALLOC=no \
        -DWITH_SYSTEMD=no \
        -DWITH_WSREP=OFF \
        -DWITH_EMBEDDED_SERVER=OFF \
        -DWITH_UNIT_TESTS=OFF \
        -DWITH_MARIABACKUP=OFF \
        -DPLUGIN_COLUMNSTORE=NO \
        -DPLUGIN_ROCKSDB=NO \
        -DPLUGIN_MROONGA=NO \
        -DPLUGIN_SPIDER=NO \
        -DPLUGIN_OQGRAPH=NO \
        -DPLUGIN_CONNECT=NO \
        -DPLUGIN_SPHINX=NO \
        -DPLUGIN_S3=NO \
        -DPLUGIN_AUTH_PAM=NO \
        -DPLUGIN_AUTH_GSSAPI=NO \
        -DPLUGIN_FEEDBACK=NO \
        -DPLUGIN_PROVIDER_SNAPPY=NO \
        -DPLUGIN_PROVIDER_BZIP2=NO \
        -DPLUGIN_PROVIDER_LZMA=NO \
        -DCMAKE_C_FLAGS="%{hardening-flags}" \
        -DCMAKE_CXX_FLAGS="%{hardening-flags}"

  build-commands:
    - ninja -C build -j%{max-jobs}

  install-commands:
    - DESTDIR="%{install-root}" ninja -C build install
    # Shell/perl helper scripts (mariadb-install-db, mysqld_safe and friends
    # when they land in scripts/) are unrunnable without a shell — pruned.
    # The bootstrap SQL they wrap stays in share/mysql (see description).
    - rm -rf "%{install-root}/usr/scripts"
    # Sacrificial support-files target (see configure-commands comment):
    # init scripts, logrotate, selinux policy sources — all dead weight here.
    - rm -rf "%{install-root}/usr/share/mariadb-support"
    # Datadir + socket dir placeholders; Kubernetes mounts volumes over both.
    # Non-root wiring (65532:65532 + /etc/passwd entry, issue #120) is Wave 3.
    - mkdir -p "%{install-root}/var/lib/mysql" "%{install-root}/run/mysqld"
    - |
      cat > "%{install-root}/etc/my.cnf" <<'EOF'
      [mysqld]
      datadir=/var/lib/mysql
      socket=/run/mysqld/mysqld.sock
      # Distroless: no local shell, clients are remote or kubectl-exec probes.
      skip-name-resolve
      EOF
