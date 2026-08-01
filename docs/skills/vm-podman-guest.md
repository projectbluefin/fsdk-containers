---
name: vm-podman-guest
description: Build the lean donate-clanker raw VM disk from FSDK.
metadata:
  context7-sources:
    - /apache/buildstream
---

# VM guest (bootable raw disk)

Use for the standalone EFI VM disk consumed by donate-clanker. The historical
`podman-vm/*` element names remain, but this guest is not a Podman host and is
not an OCI, QCOW2, or nspawn artifact.

## Element chain

`vm/minimal/deps.bst` → `podman-vm/podman-vm-deps.bst` →
`podman-vm/podman-vm-filesystem.bst` →
`podman-vm/podman-vm-efi.bst`

The base is FSDK's full VM/uutils userspace. The guest adds networking,
certificates, git, and the pinned donate-clanker worker. It deliberately has no
Podman, SSH, cloud-init, or `qemu-img`.

`podman-vm-efi.bst` stages the FSDK EFI tree and uses `genimage` to assemble a
raw GPT disk. Its install root contains only:

```text
donate-clanker-vm-<fsdk-version>-<arch>.raw
donate-clanker-vm-<fsdk-version>-<arch>.raw.sha256
```

The raw disk is booted directly by QEMU. `qemu-img` is not a build or runtime
dependency of the guest itself, but CI converts the exported raw disk to
QCOW2 with `qemu-img convert` (`just export-podman-vm-qcow2`) as a second,
smaller-footprint release asset; both formats ship with their own
`sha256sum --binary` manifest.

### Release asset contract

A GitHub Release asset is hard-capped at 2 GiB, and the raw disk is bigger
than that (an observed aarch64 build produced a 2.3G raw). The uncompressed
disk therefore cannot be an asset: the API rejects it with
`HTTP 422 ... size must be less than 2147483648`. `just compress-podman-vm`
compresses both disks with zstd (`--keep`, so the real disks stay available
for the boot test, the checksum gate, and the attestations), and the
published set per architecture is exactly:

```text
donate-clanker-vm-<fsdk-version>-<arch>.raw.zst          <- the download
donate-clanker-vm-<fsdk-version>-<arch>.raw.zst.sha256   <- verifies the download
donate-clanker-vm-<fsdk-version>-<arch>.raw.sha256       <- verifies the disk after
                                                            decompression
donate-clanker-vm-<fsdk-version>-<arch>.qcow2.zst
donate-clanker-vm-<fsdk-version>-<arch>.qcow2.zst.sha256
donate-clanker-vm-<fsdk-version>-<arch>.qcow2.sha256
podman-vm-<arch>.spdx.json
```

The URL is predictable from the version and the architecture:
`https://github.com/projectbluefin/fsdk-containers/releases/download/v<fsdk-version>/donate-clanker-vm-<fsdk-version>-<arch>.raw.zst`.
This is the shape `projectbluefin/donate-clanker` already fetches: download
`.raw.zst`, decompress, then `sha256sum -c` the `.raw.sha256` sidecar. Do not
rename these assets without changing the launcher.

The FSDK EFI tree is built separately from this element's root filesystem.
`podman-vm-efi.bst` therefore rewrites each staged loader entry's
`root=UUID=` value from the `prepare-image.sh` output before `genimage`; never
reuse an EFI tree byte-for-byte without checking it against the ext4 root UUID.

## Verification

- `BST_LOCAL=1 just bst show --deps all podman-vm/podman-vm-efi.bst`
- `just export-podman-vm` checks out the raw disk and checksum manifest.
- `just export-podman-vm-qcow2` (requires `qemu-img`/`qemu-utils`) additionally
  produces the QCOW2 conversion and its own checksum manifest.
- `tests/vm-boot.sh [disk.raw]` boots the disk under plain QEMU -- see
  "Boot test" below.
- `just compress-podman-vm` (requires `zstd`) produces the `.zst` release
  assets and their checksum manifests, keeping the originals.
- `just sbom podman-vm` generates the SPDX SBOM for the VM guest element
  (same `buildstream-sbom` tool as the OCI images; not part of the
  `elements/targets.json` OCI manifest since it isn't an OCI image).
- Confirm the worker source pin is
  `96cc69f5779d63b908d5f53957287b7ef6bda7fa`.
- Treat the observed x86_64 local benchmark (~10 minutes, 2.2G raw) as
  indicative only, not a contract.

## Boot test

`tests/vm-boot.sh` is the boot gate. It boots the disk the way the only real
consumer boots it -- `projectbluefin/donate-clanker`'s
`just/61-donate-clanker.just`:

- `qemu-system-<arch>` directly, KVM when the host offers a usable
  `/dev/kvm` for that architecture, otherwise TCG,
- EDK2/OVMF firmware as a `-drive if=pflash` CODE + writable VARS pair, with
  a single-blob `-bios` fallback,
- a per-run QCOW2 overlay, `qemu-img create -f qcow2 -F raw -b <raw>`. The
  master raw disk is **never** booted directly: writing to it breaks its
  published checksum. The test re-verifies the master's checksum after the
  boot to prove the overlay held,
- user-mode virtio networking and the virtio-serial `virtserialport` named
  `org.projectbluefin.donate-clanker.bootstrap`,
- headless, with the serial console captured to a file.

It asserts, in order, that firmware handed off to a bootloader, that the
Linux kernel started, that the initrd switched into the root filesystem, and
that the serial getty reached the login prompt.

The switch-root marker is the one that catches this guest's real failure
mode. The loader entry's `root=UUID=` and the ext4 root UUID come from two
different BuildStream builds; when they disagree the initrd waits on
`Expecting device dev-disk-by-uuid-...` forever. Observed on the published
`donate-clanker-vm-25.08.14-x86_64.raw` (built before the loader-entry
rewrite in `podman-vm-efi.bst` landed): loader entry
`root=UUID=9e71ad99-5ddc-5b20-8b9c-f3f6b4e570e1`, actual ext4 root UUID
`a5e5b74b-7aa6-58b1-8408-e4147a36da17`. The login prompt then proves the
real root userspace came up. On failure the captured serial log is printed
to stdout, so a CI failure is diagnosable without downloading an artifact.

`donate-clanker-bootstrap.service` is deliberately **not** asserted on. The
unit and its `enable` preset ship in the image, but the preset is not
applied at runtime: booting
`donate-clanker-vm-25.08.15-aarch64.raw` to a login prompt shows neither
`donate-clanker-bootstrap.service` nor `systemd-networkd` ever starting.
That is a real gap in the guest, tracked separately; asserting on it here
would fail every build for a reason no disk build can fix. Once the preset
is genuinely applied, tighten the ready marker to that unit -- it is the
better ready point.

The bootstrap virtio-serial port is wired anyway, so the guest boots against
the device topology donate-clanker gives it. Nothing is written to it: the
envelope schema belongs to donate-clanker.

There is deliberately **no Lima**. Lima expects cloud-init, an injected SSH
key, a guest agent and its own readiness probe; this guest ships none of
them, so a Lima failure never reliably meant the disk was broken. Do not
reintroduce it.

## CI pipeline

See docs/skills/ci-tooling.md for the full workflow structure. In short,
`.github/workflows/vm-guest.yml` is a reusable workflow (called from
`build.yml`) with a single matrix job (arch: x86_64, aarch64). Each leg
builds the raw disk, converts it to QCOW2, verifies both checksums,
generates the SBOM, boot-tests it under plain QEMU (both architectures, via
`tests/vm-boot.sh`), and
-- only on `push`/`workflow_dispatch` -- compresses the disks and publishes
the compressed disks, checksums, and SBOM as GitHub Release assets, then
attests them (build provenance + SBOM attestation) via `actions/attest` with
`subject-path`. Publish and attestation stay inside the same per-arch job as
steps rather than a separate downstream job, so one architecture's asset is
never stranded behind another architecture's build or test — see
"Independent architecture asset publication" in docs/skills/ci-tooling.md.

`just publish-podman-vm` publishes one architecture's set as an
all-or-nothing transaction, and the `verify-release` job fails the run when
the tag ends up missing any asset for either architecture. See "Atomic
release asset publication" in docs/skills/ci-tooling.md.
