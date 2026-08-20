---
name: vm-podman-guest
version: "1.0"
last_updated: 2026-08-20
id: vm-podman-guest
one_line_purpose: Build, boot-test and publish the podman VM guest image.
entry_point: docs/skills/vm-podman-guest/SKILL.md
category: test-authoring
mcp_compliance_level: partial
optimization_status: draft
status: active
dependencies: []
tags: [vm, testing, podman, qemu]
description: "Build the lean donate-clanker raw VM disk from FSDK."
metadata:
  type: runbook
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
`podman-vm-efi.bst` therefore rewrites the baked `root=UUID=` value from the
`prepare-image.sh` output before `genimage` -- in the UKI's `.cmdline` PE
section under FSDK 26.08 (`objcopy --update-section`, which is also where the
UKI's upstream-added `quiet` is removed so the serial console keeps emitting
the markers the boot test asserts on), or in each staged loader entry under
FSDK 25.08. The step fails the build when neither layout is found: a silent
no-op here is what shipped an unbootable disk when 26.08 moved the cmdline
into the UKI. Never reuse an EFI tree byte-for-byte without checking it
against the ext4 root UUID.

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

## Reference material

- [`references/boot-test.md`](references/boot-test.md) — VM Podman Guest — boot test and diagnostics
- [`references/bootstrap-and-ci.md`](references/bootstrap-and-ci.md) — VM Podman Guest — bootstrap contract and CI
