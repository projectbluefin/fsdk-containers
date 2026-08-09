kind: manual
description: Build nginx from source for the lab-runner utility image.

sources:
  - kind: tar
    url: https://nginx.org/download/nginx-%{nginx_version}.tar.gz
    ref: a7657c50811c2d92d9895395e8b873ef60398142c4db21eb647811c38f6dd525

build-depends:
  - freedesktop-sdk.bst:public-stacks/runtime-gnu.bst
  - freedesktop-sdk.bst:components/gcc.bst
  - freedesktop-sdk.bst:components/make.bst
  - freedesktop-sdk.bst:bootstrap/pcre2.bst
  - freedesktop-sdk.bst:components/openssl.bst
  - freedesktop-sdk.bst:components/zlib.bst
  # nginx's auto/ configure scripts and the generated objs/Makefile shell out
  # to sed, grep and awk without checking for them, so a missing one silently
  # produces an objs/Makefile with an empty object list and the build dies at
  # link time with "cc: fatal error: no input files". Declare every tool the
  # build runs (docs/skills/ci-tooling/SKILL.md, "Build-time utility dependencies").
  - freedesktop-sdk.bst:components/sed.bst
  - freedesktop-sdk.bst:components/grep.bst
  - freedesktop-sdk.bst:components/gawk.bst
  - freedesktop-sdk.bst:bootstrap/coreutils.bst

variables:
  strip-binaries: ""
  # renovate: datasource=github-tags depName=nginx/nginx extractVersion=^release-(?<version>.+)$
  nginx_version: 1.31.3

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
    - mkdir -p "%{install-root}/var/cache/nginx" "%{install-root}/etc/nginx"
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
