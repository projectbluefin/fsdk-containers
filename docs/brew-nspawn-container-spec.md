# brew-nspawn container spec

## What this is

A systemd-nspawn machine image — a rootfs tarball suitable for `machinectl import-tar` — that provides the full Homebrew developer environment for Project Bluefin/Dakota.

**This is NOT a distroless image.** It is a full dev environment container. The distroless rules (no shells, strip locales, etc.) do NOT apply. This container needs bash, a package manager runtime, compilers, and a real init.

Ships in the Dakota OCI image at `/usr/share/containers/homebrew-env.tar`. Updated independently via `systemd-sysupdate`. Also installable standalone on any systemd distro as `bluefin-cli`.

## Output format

A `.tar.gz` rootfs archive, NOT an OCI image. The BST element chain must produce a tarball that `machinectl import-tar` accepts — i.e., a complete Linux rootfs with `/etc`, `/usr`, `/bin`, `/lib`, etc.

The output goes to: `ghcr.io/projectbluefin/bluefin-cli/homebrew-env-@v.tar.gz` (versioned, with `SHA256SUMS` and `SHA256SUMS.gpg` alongside for `systemd-sysupdate`).

## Required contents

### Init system
Must have a working init so `machinectl start homebrew` succeeds. FSDK's `components/systemd.bst` if it exists, otherwise a minimal init. The container runs long-lived (always-on, started at boot via `systemd-nspawn@homebrew.service`).

### Runtime dependencies brew needs to operate
```
components/ruby.bst          # brew is written in Ruby — required at runtime
components/git.bst           # brew uses git for taps and self-update
components/curl.bst          # brew downloads bottles via curl
components/gcc.bst           # needed for source builds; also what the user gets for free
components/ca-certificates.bst  # HTTPS cert verification for brew downloads
```

### Brew itself
Stage the brew prefix into `/home/linuxbrew/.linuxbrew` during build.

Use the existing dakota pattern from `elements/bluefin/brew.bst` as reference — it pulls from `github:ublue-os/brew.git` using `kind: git_repo`. Adapt that source reference. The key is to install brew's file tree (not run install.sh at build time — that requires network in the BST sandbox).

Brew's minimal structure needed on first run:
```
/home/linuxbrew/.linuxbrew/Homebrew/          ← brew.git contents
/home/linuxbrew/.linuxbrew/bin/brew           ← symlink to Homebrew/bin/brew
/home/linuxbrew/.linuxbrew/Cellar/            ← empty dir (brew populates at runtime)
/home/linuxbrew/.linuxbrew/opt/               ← empty dir
/home/linuxbrew/.linuxbrew/lib/               ← empty dir
```

### User account
The container runs brew as the `linuxbrew` user (uid 1001, gid 1001). Create this user in `/etc/passwd` and `/etc/group` during the build. The nspawn config uses `PrivateUsers=no`, so this uid must match across host and container.

```
/etc/passwd:  linuxbrew:x:1001:1001::/home/linuxbrew:/bin/bash
/etc/group:   linuxbrew:x:1001:
/etc/subuid:  linuxbrew:100000:65536
/etc/subgid:  linuxbrew:100000:65536
```

### Shell
`bash` must be present and at `/bin/bash` — brew requires it. Do NOT strip the shell.

### Locale
Keep `en_US.UTF-8` as minimum. Brew and some formulas assume a UTF-8 locale.

## What to exclude

No desktop stack. No Wayland/Mesa/PipeWire/GTK (hard rule #1 from AGENTS.md — don't pull `platform.bst`). No X11. No audio. No printing.

No package manager (apt/dnf/etc) — brew IS the package manager for this container.

## BST element structure (suggested)

```
elements/
  brew/
    brew-deps.bst        # kind: stack — FSDK ruby, git, curl, gcc, ca-certs, systemd, bash
    brew-runtime.bst     # kind: compose — carve brew-deps to runtime domains (keep shells)
    brew-prefix.bst      # kind: manual — stage brew git repo into /home/linuxbrew prefix
    brew-users.bst       # kind: manual — /etc/passwd, /etc/group, /etc/subuid entries
  oci/
    brew-nspawn.bst      # kind: script — assemble rootfs tar (NOT OCI image)
```

## The output element (brew-nspawn.bst)

This is where it diverges from all other fsdk-containers outputs. Instead of `build-oci`, the script element must produce a `.tar.gz` of the rootfs:

```yaml
kind: script
build-depends:
  - brew/brew-runtime.bst  # filename: ..., config: location: /layer
  - brew/brew-prefix.bst   # filename: ..., config: location: /layer
  - brew/brew-users.bst    # filename: ..., config: location: /layer
config:
  commands:
    - |
      # Produce machinectl-compatible rootfs tarball
      tar -czf "%{install-root}/homebrew-env-%{version}.tar.gz" \
        -C /layer .
    - |
      # SHA256SUMS for systemd-sysupdate
      cd "%{install-root}"
      sha256sum --binary homebrew-env-%{version}.tar.gz > SHA256SUMS
```

## Working nspawn config (for reference / docs)

The consuming side (Dakota/bluefin-cli) uses this config. The container image must be compatible with it:

```ini
# /etc/systemd/nspawn/homebrew.nspawn
[Exec]
PrivateUsers=no
ResolvConf=bind-host

[Files]
Bind=/home/linuxbrew

[Network]
VirtualEthernet=no
```

`PrivateUsers=no` — host and container share UIDs. `linuxbrew` at uid 1001 in the container must match what the host bind-mounts at `/home/linuxbrew` (owned by uid 1001).

## Host wrapper (for reference)

```bash
#!/bin/bash
# /var/usrlocal/bin/brew
machinectl show homebrew &>/dev/null || machinectl start homebrew
exec systemd-run --quiet --pipe --machine=homebrew --uid=linuxbrew -- \
  /home/linuxbrew/.linuxbrew/bin/brew "$@"
```

## systemd-sysupdate transfer config (for reference)

```ini
# /usr/lib/sysupdate.d/homebrew-container.transfer
[Transfer]
ProtectVersion=%A

[Source]
Type=url-tar
Path=https://ghcr.io/projectbluefin/bluefin-cli/
MatchPattern=homebrew-env-@v.tar.gz

[Target]
Type=subvolume
Path=/var/lib/machines
MatchPattern=homebrew-@v
CurrentSymlink=/var/lib/machines/homebrew
```

## Prototype reference (ubuntu baseline)

A working ubuntu:24.04-based prototype is running on exo-1. The BST version should produce equivalent behavior. Key facts from the prototype:

- Ubuntu slim + systemd + brew bootstrap → 530MB tar (acceptable; FSDK-based should be smaller)
- `machinectl import-tar` creates btrfs subvolume automatically on btrfs hosts
- `brew install cowsay` works end-to-end through the host wrapper
- DNS: `ResolvConf=bind-host` in nspawn config handles it — no manual resolv.conf bind needed
- UID: `PrivateUsers=no` is the correct setting; `PrivateUsersOwnership=auto` does NOT fix bind-mount ownership for external paths

## Questions for the implementer

1. Does FSDK have `components/systemd.bst`? If not, what init is available?
2. Does FSDK's `components/ruby.bst` include the full runtime needed by brew, or is it split?
3. Is there a BST pattern in this repo for producing a tar output instead of OCI? If not, the `brew-nspawn.bst` script element above is the pattern to add.
4. Should the brew git ref track dakota's `elements/bluefin/brew.bst` ref, or be independently pinned?
