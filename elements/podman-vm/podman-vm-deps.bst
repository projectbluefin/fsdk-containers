kind: stack
description: |
  Dependency set for the generic, shell-enabled Podman VM guest.

  Reuses freedesktop-sdk.bst's own `vm/minimal/deps.bst` wholesale for the
  base VM contract (systemd, linux, dracut, iproute2/networkd/resolved,
  journald, useradd-default, shadow, dbus, os-release, tzdata,
  util-linux-full, base-filesystem, bash-config/completion — see that
  element for the full list) instead of re-declaring it, then layers on:

  - `components/openssh-systemd.bst` — sshd unit, sysusers, tmpfiles (its
    own runtime-dep on `components/openssh.bst` brings the ssh/sshd
    binaries). Enabled by default via `podman-vm-config.bst`'s preset
    (upstream's own preset disables it for desktop use).
  - `cloud-init/cloud-init-stack.bst` — this repo's own Task 1 Cloud-init
    component (NoCloud datasource), unmodified.
  - `components/podman.bst` plus its runtime companions listed explicitly
    below for graph legibility, even though `podman.bst` already declares
    `conmon`/`crun`/`netavark`/`passt`/`slirp4netns`/`fuse-overlayfs`/
    `iptables` as its own `runtime-depends` (verified against the pinned
    FSDK ref — see docs/skills/vm-podman-guest.md). `components/shadow.bst` is
    likewise already pulled in transitively by `vm/minimal/deps.bst`; it
    is listed here too for the same reason.
  - `podman-vm/podman-vm-config.bst` — this repo's own generic guest
    defaults (SSH-enabled preset, user Podman socket preset, writable
    container storage tmpfiles rule).

  FSDK ships no standalone `nftables` CLI component: netavark's firewall
  backend talks to the kernel nftables netlink API directly via its own
  vendored Rust `nftables` crate (see `components/netavark.bst`'s
  `Cargo.lock`), not the `nft`/`iptables` command-line tools. `iptables.bst`
  (nftables-backed `iptables` compat binary, via `libnftnl`) is depended on
  here anyway because `components/podman.bst` itself runtime-depends on it
  for CNI-adjacent/legacy firewall paths.

depends:
- freedesktop-sdk.bst:vm/minimal/deps.bst
- freedesktop-sdk.bst:components/openssh-systemd.bst
- cloud-init/cloud-init-stack.bst
- freedesktop-sdk.bst:components/podman.bst
- freedesktop-sdk.bst:components/conmon.bst
- freedesktop-sdk.bst:components/crun.bst
- freedesktop-sdk.bst:components/fuse-overlayfs.bst
- freedesktop-sdk.bst:components/slirp4netns.bst
- freedesktop-sdk.bst:components/passt.bst
- freedesktop-sdk.bst:components/netavark.bst
- freedesktop-sdk.bst:components/iptables.bst
- freedesktop-sdk.bst:components/shadow.bst
- podman-vm/podman-vm-config.bst
- podman-vm/donate-clanker-vm-config.bst
- podman-vm/donate-clanker-worker.bst
