kind: script
description: |
  Assemble the Homebrew nspawn machine image as a machinectl-compatible rootfs
  tarball (NOT an OCI image). Stages the homebrew runtime rootfs and the brew
  prefix at /layer, applies the shared rootfs finalisation, adds the bits only
  a booted machine needs (init symlink, machine-id), then emits
  homebrew-env-<ver>.tar.zst + SHA256SUMS for systemd-sysupdate.

  Sibling: elements/oci/homebrew.bst packages the SAME rootfs as an OCI image.
  Anything that must be true of both belongs in include/homebrew-rootfs.yml.

build-depends:
  # Root toolchain to run the assembly commands (coreutils, bash, tar, zstd).
  - base/base-stack.bst
  - freedesktop-sdk.bst:components/tar.bst
  - freedesktop-sdk.bst:components/zstd.bst
  # The rootfs content, staged into /layer.
  - filename: homebrew/homebrew-runtime.bst
    config:
      location: /layer
  - filename: homebrew/homebrew-prefix.bst
    config:
      location: /layer

variables:
  (@): include/homebrew-rootfs.yml
  brew-version: "6.0.3"

config:
  commands:
    # --- Shared rootfs finalisation (linuxbrew user, locale) ---
    - "%{homebrew-rootfs-commands}"

    - |
      set -eu
      L=/layer

      # --- init: machinectl/systemd-nspawn boot needs /sbin/init ---
      # Machine-image only: the OCI image is not booted by systemd.
      if [ ! -e "$L/sbin/init" ]; then
        if [ -e "$L/usr/lib/systemd/systemd" ]; then
          ln -sf /usr/lib/systemd/systemd "$L/sbin/init"
        fi
      fi

      # --- machine-id: empty triggers systemd first-boot provisioning per machine ---
      : > "$L/etc/machine-id"

    - |
      set -eu
      cd "%{install-root}"
      TARBALL="homebrew-env-%{brew-version}.tar.zst"

      # machinectl import-tar wants a complete rootfs tarball with numeric owners.
      # zstd: 3-5x faster decompression than gzip; systemd-sysupdate handles .tar.zst.
      tar --numeric-owner --xattrs --zstd -cf "$TARBALL" -C /layer .

      # Checksums for systemd-sysupdate (SHA256SUMS / SHA256SUMS.gpg alongside).
      sha256sum --binary "$TARBALL" > SHA256SUMS
