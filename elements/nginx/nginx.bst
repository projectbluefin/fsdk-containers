kind: manual
description: |
  Build nginx from source for the standalone distroless nginx image.
  Adapted from lab-runner/nginx.bst; the differences from the lab-runner
  copy are the explicitly declared runtime libraries (the lab-runner stack
  receives libpcre2/libssl/libz transitively via curl/git, a standalone
  image must declare them itself), compiler hardening flags, and shipped
  default content at the conventional /usr/share/nginx/html path.

  Wave 0 feasibility spike (#146) — the four answers, re-verified
  2026-08-20 on branch spike-146-nginx:

  1. Mechanism: TARBALL source build (kind: manual + tar source from
     nginx.org). freedesktop-sdk does NOT ship nginx — no
     elements/components/nginx.bst exists on the junction
     (gitlab.com/freedesktop-sdk/freedesktop-sdk@master, checked
     2026-08-20 via the repository API), so the FSDK-component path used
     by curl/go is not available. This CONFIRMS #113's Wave-4 batch-B
     assumption ("Tarball source build ... proven via lab-runner") —
     no mechanism correction required.
  2. Exact dependency set — build-depends: runtime-gnu (shell+coreutils
     stack), gcc, make, sed, grep, gawk, bootstrap/coreutils (the auto/
     configure scripts shell out to sed/grep/awk unchecked — see below).
     depends (build AND runtime): bootstrap/libxcrypt (REQUIRED, gcc's
     runtime dep stages libcrypt.so.2 in the sandbox so configure links
     crypt() — without it the built binary dies with "error while loading
     shared libraries: libcrypt.so.2"), bootstrap/pcre2,
     components/openssl, components/zlib. The stack
     (nginx-stack.bst) composes this on base/base-stack.bst.
  3. Resolves: YES — and builds on the ghost BuildBarn grid:
     `just bst build elements/nginx/nginx-stack.bst` (remote execution
     default, BST_LOCAL unset) succeeded on 2026-08-20.
  4. Upstream version + verifiable ref: nginx 1.31.3 (mainline), tar
     sha256 a7657c50811c2d92d9895395e8b873ef60398142c4db21eb647811c38f6dd525,
     re-verified live 2026-08-20:
     curl -sL https://nginx.org/download/nginx-1.31.3.tar.gz | sha256sum
     (elements/lab-runner/nginx.bst moved to 1.31.4 in #172; this spike
     element stays on the version it verified — renovate tracks the
     variable below and will propose bumps.)

sources:
  - kind: tar
    url: https://nginx.org/download/nginx-%{nginx_version}.tar.gz
    # sha256 verified live 2026-08-09:
    # curl -sL https://nginx.org/download/nginx-1.31.3.tar.gz | sha256sum
    ref: a7657c50811c2d92d9895395e8b873ef60398142c4db21eb647811c38f6dd525

build-depends:
  - freedesktop-sdk.bst:public-stacks/runtime-gnu.bst
  - freedesktop-sdk.bst:components/gcc.bst
  - freedesktop-sdk.bst:components/make.bst
  # nginx's auto/ configure scripts and the generated objs/Makefile shell out
  # to sed, grep and awk without checking for them, so a missing one silently
  # produces an objs/Makefile with an empty object list and the build dies at
  # link time with "cc: fatal error: no input files". Declare every tool the
  # build runs (docs/skills/ci-tooling/SKILL.md, "Build-time utility dependencies").
  - freedesktop-sdk.bst:components/sed.bst
  - freedesktop-sdk.bst:components/grep.bst
  - freedesktop-sdk.bst:components/gawk.bst
  - freedesktop-sdk.bst:bootstrap/coreutils.bst

# Runtime libraries nginx links against. Plain `depends:` (type "all") stages
# their headers in the build sandbox AND lands the shared libraries in the
# composed image (BuildStream format_declaring docs). bootstrap/* as runtime
# deps is FSDK's own pattern: components/grep.bst -> bootstrap/grep.bst ->
# runtime-depends bootstrap/pcre2.bst, and their bootstrap/glibc.bst
# runtime-dep dedupes against base-stack's (runtime-minimal is bootstrap
# glibc).
#
# libxcrypt is REQUIRED, not optional: components/gcc.bst runtime-depends on
# bootstrap/libxcrypt.bst, so libcrypt.so.2 is staged in the build sandbox,
# nginx's configure finds crypt(), and the binary ends up with
# NEEDED libcrypt.so.2 (verified via readelf on the grid-built artifact).
# Without this dep the image's nginx fails at startup with
# "error while loading shared libraries: libcrypt.so.2".
depends:
  - freedesktop-sdk.bst:bootstrap/libxcrypt.bst
  - freedesktop-sdk.bst:bootstrap/pcre2.bst
  - freedesktop-sdk.bst:components/openssl.bst
  - freedesktop-sdk.bst:components/zlib.bst

variables:
  strip-binaries: ""
  # renovate: datasource=github-tags depName=nginx/nginx extractVersion=^release-(?<version>.+)$
  nginx_version: 1.31.3
  hardening-flags: ""
  (?):
    - arch == "x86_64":
        hardening-flags: "-fstack-protector-strong -fstack-clash-protection -D_FORTIFY_SOURCE=3 -fcf-protection=full"
    - arch == "aarch64":
        hardening-flags: "-fstack-protector-strong -fstack-clash-protection -D_FORTIFY_SOURCE=3 -mbranch-protection=standard"

config:
  configure-commands:
    - |
      # --sbin-path lands in /usr/bin, not /usr/sbin: freedesktop-sdk is a
      # merged-usr sysroot where /usr/sbin is a symlink to /usr/bin, and
      # staging a real usr/sbin directory fails with "Destination is a
      # symlink, not a directory: /usr/sbin".
      ./configure \
        --prefix=/usr \
        --sbin-path=/usr/bin/nginx \
        --conf-path=/etc/nginx/nginx.conf \
        --pid-path=/run/nginx.pid \
        --lock-path=/run/nginx.lock \
        --error-log-path=/dev/stderr \
        --http-log-path=/dev/stdout \
        --http-client-body-temp-path=/var/cache/nginx/client_temp \
        --http-proxy-temp-path=/var/cache/nginx/proxy_temp \
        --http-fastcgi-temp-path=/var/cache/nginx/fastcgi_temp \
        --http-uwsgi-temp-path=/var/cache/nginx/uwsgi_temp \
        --http-scgi-temp-path=/var/cache/nginx/scgi_temp \
        --with-cc-opt="%{hardening-flags}" \
        --with-http_ssl_module \
        --with-http_v2_module \
        --with-pcre-jit \
        --with-threads \
        --with-compat \
        --without-http_autoindex_module \
        --without-http_ssi_module \
        --without-http_userid_module

  build-commands:
    - make -j%{max-jobs}

  install-commands:
    - make install DESTDIR="%{install-root}"
    - mkdir -p "%{install-root}/var/cache/nginx" "%{install-root}/etc/nginx" "%{install-root}/usr/share/nginx/html"
    # `make install` drops the upstream welcome page at %{prefix}/html; the
    # conventional content path for nginx containers (upstream image, k8s
    # examples) is /usr/share/nginx/html. Ship one intentional default page
    # there instead of two copies of upstream's.
    - rm -rf "%{install-root}/usr/html"
    - |
      cat > "%{install-root}/usr/share/nginx/html/index.html" <<'EOF'
      <!doctype html>
      <html><head><title>nginx on fsdk-containers</title></head>
      <body><h1>nginx on fsdk-containers</h1>
      <p>Distroless nginx carved from freedesktop-sdk. Replace
      /usr/share/nginx/html with your content.</p></body></html>
      EOF
    # Unprivileged listen port (8080, not 80) so the image can run as the
    # catalog non-root UID 65532 without cap_net_bind_service (#120).
    # No `user` directive: a non-root master cannot setuid and the directive
    # would only warn. Foreground mode is set by the image entrypoint
    # (`nginx -g 'daemon off;'`), matching upstream container practice.
    - |
      cat > "%{install-root}/etc/nginx/nginx.conf" <<'EOF'
      worker_processes auto;
      error_log /dev/stderr;
      events { worker_connections 1024; }
      http {
        access_log /dev/stdout;
        include /etc/nginx/mime.types;
        default_type application/octet-stream;
        sendfile on;
        server { listen 8080; root /usr/share/nginx/html; }
      }
      EOF
