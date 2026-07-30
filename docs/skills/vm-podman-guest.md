---
name: vm-podman-guest
description: Build a generic, shell-enabled bootable EFI/QCOW2 VM guest (Podman host) from FSDK, composed entirely from components/* and the vm/minimal/* reference. Use when adding a VM disk image (not an OCI image, not an nspawn tarball) that must boot standalone under QEMU/EFI.
metadata:
  context7-sources:
    - /apache/buildstream
---

# VM Podman Guest (bootable EFI/QCOW2 disk image)

Use when the deliverable is a **standalone bootable VM disk image** — a
`.qcow2` you hand to QEMU/libvirt/Lima, not an OCI image (`add-new-image.md`)
and not an `systemd-nspawn` tarball (`nspawn-machine-image.md`). Reference
implementation: `elements/podman-vm/*`, built from FSDK's own
`vm/minimal/efi.bst` reference chain plus this project's own
`elements/qemu-img/qemu-img-stack.bst` and `elements/cloud-init/*`.

## When NOT to use

- A normal OCI container image → `add-new-image.md`.
- A dev-environment tarball for `machinectl import-tar` → `nspawn-machine-image.md`.
- Anything involving specific users, SSH keys, contributor/Hive wiring, or a
  workspace mount → that is a **separate, later** layer built on top of this
  generic guest. Keep this element chain user- and secret-free.

## Element chain (mirrors upstream `vm/minimal/*`, do not reinvent it)

1. `podman-vm-config.bst` (`manual`) — the *only* genuinely new "guest
   defaults" logic: installs `*.preset` and `tmpfiles.d` files from
   `kind: local` sources. **`kind: local` paths are relative to the
   project root, not the element's directory** — write
   `path: elements/podman-vm/files/podman-vm-config/foo` even from inside
   `elements/podman-vm/podman-vm-config.bst`. Local sources flatten to
   basename at sandbox root with no `directory:` override, so give every
   source file a distinct name even if their installed names differ.
2. `podman-vm-deps.bst` (`stack`) — depends on
   `freedesktop-sdk.bst:vm/minimal/deps.bst` (the base VM contract: systemd,
   linux, dracut, networking, journald, useradd-default, shadow, dbus,
   os-release, tzdata, base-filesystem) plus the Podman runtime component set
   (`podman`, `conmon`, `crun`, `fuse-overlayfs`, `slirp4netns`, `passt`,
   `netavark`, `iptables`, `shadow`), `openssh-systemd`, this project's
   `cloud-init/cloud-init-stack.bst`, and `podman-vm-config.bst`.
3. `podman-vm-filesystem.bst` (`compose`) — chisel step, mirrors upstream
   `vm/minimal/filesystem.bst`'s `exclude: [debug, devel, doc, tests, shells]`.
   The `shells` domain does **not** remove `bash` (AGENTS.md rule 4: `bash`
   lives in the `runtime` split domain) — this is a VM guest, not a
   distroless image, so a shell is expected and required.
4. `podman-vm-initial-scripts.bst` (`collect_initial_scripts`) — collects
   `public.initial-script` hooks (e.g. shadow's `setcap` for
   `newuidmap`/`newgidmap`) from the full deps graph. Required for rootless
   Podman.
5. `podman-vm-efi.bst` (`script`) — the assembly element. Stage
   `podman-vm-filesystem.bst` at `/sysroot`, reuse
   `freedesktop-sdk.bst:vm/boot/efi.bst` byte-for-byte at `/sysroot/efi`,
   stage `qemu-img/qemu-img-stack.bst` at an **isolated** location (e.g.
   `/opt/qemu-img`, invoked by full path) to avoid file overlap with
   `vm/deploy-tools.bst`'s own root-staged closure. Reuse
   `freedesktop-sdk.bst:vm/prepare-image.bst`'s `prepare-image.sh` and
   `genimage` invocation unchanged, except point `genimage.cfg`'s
   `outputpath` at `%{build-root}` (not `%{install-root}`) so the raw
   `disk.img` GPT/EFI image is a **build-only intermediate**, then convert
   it with the staged `qemu-img convert -f raw -O qcow2 -o compat=1.1` into
   the final `install-root` artifact, and emit a `sha256sum --binary`
   manifest alongside it.

## Guest-default decisions (generic only — no users/keys/Hive here)

- **SSH enabled by default**: upstream `components/openssh-systemd.bst`
  ships a `disable sshd.service` preset (desktop-oriented). systemd merges
  every `*.preset` file across `/etc`, `/run`, and
  `/usr/lib/systemd/{system,user}-preset` into one alphabetically sorted
  list — the first matching file wins regardless of directory. Ship
  `00-podman-vm.preset` (sorts before `openssh.preset`) with
  `enable sshd.service` to override it.
- **User Podman socket enabled by default**: `podman.bst`'s `make-install`
  override is *additive* (`make -j1 %{make-install-args} install.completions`
  still expands the default `make-install-args`, so `make install` — which
  includes `install.systemd` — still runs). The unit files
  (`podman.socket`/`podman.service`, system **and** user) are already
  installed; only *enabling* them was missing. Ship
  `enable podman.socket` in a `00-podman-vm.preset` under
  `user-preset`. `vm/prepare-image.bst`'s `prepare-image.sh` already runs
  both `systemctl --root preset-all` and
  `systemctl --root --global preset-all` — the `--global` run makes this
  apply to every current *and future* user, so no per-user provisioning
  step is needed here.
- **No standalone `nftables` component exists in FSDK.**
  `components/netavark.bst`'s own Rust `nftables` crate (netlink-based) is
  the real firewall backend Podman uses; `components/iptables.bst`
  (nftables-backed compat binary) is already `podman.bst`'s own
  `runtime-depends`. Don't go looking for a missing `nft` CLI component —
  it isn't needed and doesn't exist upstream.
- **Writable rootless container storage**: ship a `tmpfiles.d` snippet
  creating `/var/lib/containers/{storage,cache}` (the system-wide fallback
  path); per-user rootless storage under `$HOME/.local/share/containers`
  needs no pre-creation — Cloud-init's `cc_users_groups` module creates
  each user's home directory (already writable) when it provisions a user.

## Hard-won gotchas

- **FSDK project-scoped variables are invisible outside FSDK's own project.**
  `%{linux-root}`, `%{indep-libdir}`, and — critically — `%{source-date-epoch}`
  are defined in FSDK's own `project.conf`/includes and are **not** resolved
  when referenced from YAML physically located in the consuming project, even
  while staging/depending on FSDK elements. Follow this repo's existing
  precedent (`elements/cloud-init/systemd-unitdir-pkgconfig.bst`): hardcode
  the literal value locally instead (e.g.
  `source-date-epoch: '1321009871'`, matching BuildStream's own core builtin
  `SOURCE_DATE_EPOCH` default — note this is a **different literal** than
  FSDK's own `1320937200`, which is fine; it only needs to be stable, not
  identical to FSDK's).
- **`%{prefix}`, `%{bindir}` etc. are genuine BuildStream core builtins** and
  would resolve fine, but this repo's convention (per the cloud-init
  precedent) is to hardcode `/usr/...` paths anyway for clarity.
- **`disk.img` as a build-only intermediate**: unlike upstream's
  `vm/minimal/efi.bst`, where `disk.img` *is* the element's install-root
  output, a Podman-VM-style element that must emit a qcow2 should redirect
  `genimage.cfg`'s `outputpath` to `%{build-root}`, keeping `install-root`
  limited to the final `<name>-<version>-<arch>.qcow2` + `.sha256`.
- **Fixed UUID namespace for reproducibility, with full artifact identity
  folded into every derived name**: derive disk/partition/filesystem UUIDs
  from a UUIDv5 namespace generated once and hardcoded (e.g.
  `uuidgen -s --namespace @url --name "https://github.com/<org>/<repo>/<image-name>"`),
  **but never derive a UUID from the namespace alone** — every
  `uuidgen -s --namespace "%{uuidnamespace}" --name "..."` call must fold
  the exact artifact identity (point release + arch + role, e.g.
  `podman-vm-25.08.14-x86_64-disk`) into the `--name` string. UUIDv5 is a
  deterministic hash of `namespace + name`: identical inputs always
  reproduce the identical UUID (safe for repeatable builds), but if two
  different (version, arch) builds pass the *same* name string, they get
  the *same* disk/partition/hash-seed UUID — a real bug (silently
  colliding GPT disk UUIDs are a genuine hazard for tooling that
  identifies disks by UUID, e.g. `libvirt`/`blkid`/`fstab`). Verify this
  statically without a full build: compute the same `uuidgen -s
  --namespace <ns> --name <id>-<role>` formula for a matrix of
  (version, arch) pairs with plain shell + `uuidgen`, and confirm (a)
  repeated runs of the same pair reproduce identical UUIDs, and (b) every
  pair produces UUIDs that are pairwise distinct from every other pair,
  per role.
  **This full-identity rule also applies to any upstream helper script
  that takes a `--seed`-style argument and internally treats it as a
  UUIDv5 *namespace*** — e.g. freedesktop-sdk.bst's own
  `files/vm/prepare-image.sh` takes `--seed` and uses it directly as
  `uuidgen -s --namespace "${seed}" --name root|efi|salt` to derive the
  ext4 root filesystem UUID, EFI volume ID, and root password salt.
  Passing a fixed, artifact-family-wide namespace straight through as
  that `--seed` reproduces the exact same collision bug one level deeper
  (every point release/arch gets the identical root/EFI/salt identity)
  even after the disk/partition UUIDs above are fixed correctly — read
  any such script's own source to see what it does with `--seed`/similar
  flags before assuming a fixed namespace value is safe to hand it
  directly. The fix is the same shape: derive a
  per-artifact seed first
  (`uuidgen -s --namespace <fixed-ns> --name "<id>-<version>-<arch>"`)
  and pass *that* as the `--seed` value, so the script's own internal
  namespace-based derivations inherit the full identity too. Verify by
  reproducing the script's exact internal formula (namespace = computed
  artifact seed, name = whatever the script itself uses, e.g. `root`/
  `efi`/`salt`) across the same (version, arch) matrix and checking both
  properties again.
- **FSDK exact point release, reused from the Justfile, not
  re-parsed**: the Justfile's `fsdk_version` (git-describe parse of
  `elements/freedesktop-sdk.bst`'s `ref:`, e.g. `25.08.14`) is this repo's
  established single source of truth for FSDK versioning (already used
  for OCI image labels/tags). A BuildStream element has no shell-level
  access to that file from inside the sandbox, and reading
  `/sysroot/etc/os-release`'s `VERSION_ID` only yields FSDK's coarser
  minor-branch precision (e.g. `25.08`) — **do not use `VERSION_ID`** if
  the element needs the exact pinned point release. Instead, reuse the
  Justfile's own parser: have the `just bst` wrapper recipe regenerate a
  small, gitignored include file (e.g. `include/fsdk-version.yml`,
  containing just `fsdk-version: "<value>"`) from `{{fsdk_version}}` on
  every invocation, then pull it into the element's own `variables:`
  block with `(@): include/fsdk-version.yml` (BuildStream's per-element
  include composition — same mechanism this repo already uses for
  `include/slim.yml`). This guarantees the value can never drift from the
  Justfile's parse, without adding a second parser. Note: BuildStream
  project options have **no free-form string type** (only `bool`, `enum`,
  `flags`, `arch`, `os`, `element-mask` — confirmed against BuildStream's
  own `_options/` source), so `--option` cannot carry an arbitrary
  point-release string; the include-file-regenerated-by-Justfile pattern
  above is the correct alternative. Verify with
  `bst show --deps none --format '%{vars}' <element>.bst | grep fsdk-version`
  (note: `bst show --format` only expands a handful of built-in fields
  like `%{name}`/`%{state}`/`%{vars}` — arbitrary `%{my-var}` placeholders
  are **not** substituted directly in `--format` strings; dump `%{vars}`
  and grep it instead).
- **Go-toolchain components can fail to build under this repo's
  remote-execution (BuildBarn/RBE) cluster** with
  `go: cannot find GOROOT directory: 'go' binary is trimmed and GOROOT is
  not set`. This reproduced building `freedesktop-sdk.bst:components/podman.bst`
  (a stock, unmodified upstream element) — `components/go.bst` exports
  `GOROOT_BOOTSTRAP` for its own build but does not export a `GOROOT` in its
  public `environment:` for downstream Go-based consumers (`podman`,
  `netavark`, `aardvark-dns`, `containers-common`, ...), and the `go` binary
  relies on locating itself relative to its own file path at runtime — a
  known class of Go/remote-execution interaction (binaries built with
  trimmed paths cannot self-locate `GOROOT` when staged at a different path
  than where they were built). This is an FSDK-upstream/RBE-environment gap,
  **not** something to patch inside the vendored junction from this repo.
  If you hit this again: confirm it's still upstream-only (do not modify
  `freedesktop-sdk.bst:components/go.bst` from this repo), and consider
  filing it upstream or exporting `GOROOT` via a local override element
  (`(<):` composition over the upstream element) scoped to just the
  consuming stack, if a real build is ever required in this environment.

## Verification performed

- `just bst show --deps none podman-vm/podman-vm-efi.bst` — single-element
  load/resolve, catches syntax and immediate reference errors fast.
- `just bst show --deps all podman-vm/podman-vm-efi.bst` — full transitive
  graph resolution (397 elements): confirms every named FSDK component from
  the design brief is actually reachable and every reference resolves, with
  no missing-element or option errors.
- `just bst build podman-vm/podman-vm-efi.bst` — real build attempt.
  `podman-vm-config.bst` (this task's only new non-declarative logic) built
  and cached successfully; `bst artifact checkout` confirmed the exact
  expected installed paths and preset/tmpfiles content. The build correctly
  stopped before reaching `podman-vm-deps.bst`/`-filesystem.bst`/`-efi.bst`
  because of the upstream `podman.bst`/Go-toolchain RBE failure above — this
  is expected BuildStream dependency-failure propagation, not a graph or
  composition defect in this task's own elements.
- `just bst show --deps none --format '%{vars}' podman-vm/podman-vm-efi.bst`
  — confirms `fsdk-version` resolves to the exact pinned point release
  (matches the Justfile's `fsdk_version` byte-for-byte), proving the
  exact-version property statically without a full build.
- A local `uuidgen -s --namespace <fixed-ns> --name <artifact-id>-<role>`
  matrix (same formula as the element's own shell commands) across several
  (version, arch) pairs, checked programmatically for (a) reproducibility
  of repeated runs and (b) pairwise distinctness across pairs, per role —
  proves the UUID-uniqueness property statically without a full build.
- A second local matrix reproducing `prepare-image.sh`'s own internal
  formula (`artifact_seed = uuidgen(fixed-ns, "<artifact-id>")`, then
  `uuid_root = uuidgen(artifact_seed, "root")`,
  `id_efi/uuid_efi = uuidgen(artifact_seed, "efi")`,
  `salt = uuidgen(artifact_seed, "salt")`) across the same (version, arch)
  pairs — checked programmatically for the same two properties — proves
  the ext4 root UUID / EFI volume ID / root-password-salt identities
  (derived by the upstream script from the `--seed` argument, not
  visible to this element's own `uuidgen` calls) are also reproducible
  per-build and collision-free across distinct FSDK point releases and
  architectures.
- `just validate` (the repo's existing 7-OCI-image graph check) still
  resolves cleanly after the shared `Justfile`/`.gitignore` changes — no
  regression to the unrelated OCI image elements.
- **Not done, and not claimed**: a completed `podman-vm-efi.bst` artifact
  checkout, a genimage/qemu-img conversion run, or any VM boot. Do not claim
  these until the upstream Go-toolchain/RBE gap above is resolved in this
  environment (or the build is run with `BST_LOCAL=1`, untested here due to
  cost).
