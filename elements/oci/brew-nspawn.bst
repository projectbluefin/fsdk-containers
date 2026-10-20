kind: script
description: |
  Assemble both the existing machinectl rootfs tar and an immutable EROFS raw
  machine. The tar retains /home/linuxbrew/.linuxbrew; the raw places the same
  Git-backed prefix under /usr/share/bluefin/homebrew-seed for host provisioning
  into a persistent writable prefix. Both contain a real system and user bus,
  PAM, logind, and the complete Homebrew runtime (no installed formulae).

build-depends:
  # Root toolchain to run the assembly commands (coreutils, bash, tar, zstd).
  - base/base-stack.bst
  - freedesktop-sdk.bst:components/tar.bst
  - freedesktop-sdk.bst:components/zstd.bst
  - freedesktop-sdk.bst:components/erofs-utils.bst
  # The rootfs content, staged into /layer.
  - filename: brew/brew-runtime.bst
    config:
      location: /layer
  - filename: brew/brew-prefix.bst
    config:
      location: /layer

variables:
  # Must equal brew-prefix.bst's source track (tests/test_brew_version_pin.py).
  # renovate: datasource=github-tags depName=Homebrew/brew
  brew-version: "7.0.10"

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
      rm -f "$L/etc/shadow" "$L/etc/nsswitch.conf"
      printf 'root:!:1:0:99999:7:::\nlinuxbrew:!:1:0:99999:7:::\n' > "$L/etc/shadow"
      chmod 0600 "$L/etc/shadow"
      printf 'passwd: files systemd\ngroup: files systemd\nshadow: files\nhosts: files dns\nnetworks: files\n' > "$L/etc/nsswitch.conf"

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

      # Explicit boot/session prerequisites, rather than relying on presets
      # from a desktop distribution. FSDK systemd already enables PAM.
      mkdir -p "$L/etc/systemd/system/sockets.target.wants" \
        "$L/etc/systemd/system/multi-user.target.wants" \
        "$L/etc/systemd/user/sockets.target.wants" \
        "$L/var/lib/systemd/linger" "$L/etc/pam.d"
      ln -sf /usr/lib/systemd/system/dbus.socket "$L/etc/systemd/system/sockets.target.wants/dbus.socket"
      ln -sf /usr/lib/systemd/system/dbus.service "$L/etc/systemd/system/dbus.service"
      ln -sf /usr/lib/systemd/system/systemd-logind.service "$L/etc/systemd/system/multi-user.target.wants/systemd-logind.service"
      ln -sf /usr/lib/systemd/user/dbus.socket "$L/etc/systemd/user/sockets.target.wants/dbus.socket"
      ln -sf /usr/lib/systemd/user/dbus.service "$L/etc/systemd/user/dbus.service"
      # Retain systemd's complete upstream systemd-user PAM stack (including
      # pam_rootok for pam_setcred), not a second reduced authentication stack.
      if [ ! -e "$L/etc/pam.d/systemd-user" ]; then
        test -s "$L/usr/lib/pam.d/systemd-user"
        ln -sf /usr/lib/pam.d/systemd-user "$L/etc/pam.d/systemd-user"
      fi
      : > "$L/var/lib/systemd/linger/linuxbrew"

    - |
      set -eu
      cd "%{install-root}"
      TARBALL="homebrew-env-%{brew-version}.tar.zst"
      RAW="homebrew-env-%{brew-version}.raw"
      SEED=/layer/usr/share/bluefin/homebrew-seed
      PREFIX=/layer/home/linuxbrew/.linuxbrew

      # Preserve the existing tar contract without a second copy of the seed.
      rmdir "$PREFIX"
      mv "$SEED" "$PREFIX"
      ZSTD_NBTHREADS=1 tar --sort=name --mtime='@0' --format=pax \
        --pax-option='exthdr.name=%d/PaxHeaders/%f,delete=atime,delete=ctime' \
        --numeric-owner --owner=0 --group=0 --xattrs --zstd -cf "$TARBALL" -C /layer .
      mv "$PREFIX" "$SEED"
      mkdir -p "$PREFIX"

      # Plain filesystem images are nspawn --image compatible. Fixed UUID,
      # timestamps, and root ownership make EROFS assembly reproducible.
      mkfs.erofs --all-root -T 0 -U 54e841c8-cf38-5ee1-9caf-466649f86612 "$RAW" /layer
      fsck.erofs "$RAW"
      zstd -T1 -19 --rm "$RAW"
      sha256sum --binary "$TARBALL" "$RAW.zst" > SHA256SUMS
