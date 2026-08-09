kind: script
description: |
  Assemble the Homebrew nspawn machine image as a machinectl-compatible rootfs
  tarball (NOT an OCI image). Stages the brew runtime rootfs and the brew prefix
  at /layer, finalises the container-specific bits that need to live in the image
  (linuxbrew user, init symlink, machine-id, locale), then emits
  homebrew-env-<ver>.tar.zst + SHA256SUMS for systemd-sysupdate.

build-depends:
  # Root toolchain to run the assembly commands (coreutils, bash, tar, zstd).
  - base/base-stack.bst
  - freedesktop-sdk.bst:components/tar.bst
  - freedesktop-sdk.bst:components/zstd.bst
  # The rootfs content, staged into /layer.
  - filename: brew/brew-runtime.bst
    config:
      location: /layer
  - filename: brew/brew-prefix.bst
    config:
      location: /layer

variables:
  brew-version: "6.0.3"

config:
  commands:
    - |
      set -eu
      L=/layer

      # --- linuxbrew user (uid/gid 1001); PrivateUsers=no requires a stable uid ---
      # Authoritative minimal passwd/group. systemd-sysusers regenerates the
      # service users (systemd-network, etc.) from sysusers.d on first boot.
      # No grep: the assembly toolchain (runtime-minimal) has coreutils, not grep.
      mkdir -p "$L/etc" "$L/home/linuxbrew" "$L/root" "$L/sbin"
      # Unlink before writing. Every path under $L that already exists is a
      # *staged* file, hardlinked out of bb_worker's file pool
      # (/var/lib/buildbarn/worker/cache). `>` truncates and rewrites the inode
      # in place, and because runner.jsonnet chroots as uid 0 the read-only bit
      # does not stop it -- so an in-place write corrupts the pool entry that
      # every other build on that node hardlinks for the same digest.
      #
      # This is not hypothetical: FSDK ships /etc/subuid empty, so writing it in
      # place stored 23 bytes under the *empty-file* digest and every zero-byte
      # file staged on that worker afterwards came back as
      # `linuxbrew:100000:65536`. It surfaced as python3 failing to import a
      # 0-byte compression/__init__.py, on a completely unrelated image.
      # `rm -f` breaks the link first, so the write lands on a fresh inode.
      rm -f "$L/etc/passwd" "$L/etc/group" "$L/etc/subuid" "$L/etc/subgid"
      printf 'root:x:0:0:root:/root:/bin/bash\nlinuxbrew:x:1001:1001::/home/linuxbrew:/bin/bash\n' > "$L/etc/passwd"
      printf 'root:x:0:\nlinuxbrew:x:1001:\n' > "$L/etc/group"
      echo 'linuxbrew:100000:65536' > "$L/etc/subuid"
      echo 'linuxbrew:100000:65536' > "$L/etc/subgid"

      # Ownership of /home/linuxbrew is NOT set here: the bst sandbox runs in a
      # user namespace that cannot chown to uid 1001 (chown returns EINVAL). At
      # runtime the host establishes ownership via PrivateUsers=no + the
      # Bind=/home/linuxbrew mount (host dir owned by uid 1001 is bound in).

    - |
      set -eu
      L=/layer

      # --- init: machinectl/systemd-nspawn boot needs /sbin/init ---
      if [ ! -e "$L/sbin/init" ]; then
        if [ -e "$L/usr/lib/systemd/systemd" ]; then
          ln -sf /usr/lib/systemd/systemd "$L/sbin/init"
        fi
      fi

      # --- machine-id: empty triggers systemd first-boot provisioning per machine ---
      # `rm -f` first, not a bare `: >`: truncating in place would rewrite the
      # staged file's pool inode (see the /etc/passwd block above) and store
      # zero bytes under whatever digest the original machine-id had.
      rm -f "$L/etc/machine-id"
      : > "$L/etc/machine-id"

      # --- locale: utf-locale provides C.UTF-8 (a real UTF-8 locale brew is happy with) ---
      rm -f "$L/etc/locale.conf"
      echo 'LANG=C.UTF-8' > "$L/etc/locale.conf"

    - |
      set -eu
      cd "%{install-root}"
      TARBALL="homebrew-env-%{brew-version}.tar.zst"

      # machinectl import-tar wants a complete rootfs tarball with numeric owners.
      # zstd: 3-5x faster decompression than gzip; systemd-sysupdate handles .tar.zst.
      tar --numeric-owner --xattrs --zstd -cf "$TARBALL" -C /layer .

      # Checksums for systemd-sysupdate (SHA256SUMS / SHA256SUMS.gpg alongside).
      sha256sum --binary "$TARBALL" > SHA256SUMS
