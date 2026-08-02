---
name: vm-podman-guest
description: Build the lean donate-clanker raw VM disk from FSDK.
metadata:
  context7-sources:
    - /apache/buildstream
    - /python/cpython
---

# VM guest (bootable raw disk)

## When to Use

Use when changing, exporting, testing, or publishing the standalone EFI VM disk
consumed by donate-clanker. The historical `podman-vm/*` element names remain,
but this guest is not a Podman host and is not an OCI, QCOW2, or nspawn
artifact.

## When NOT to Use

Do not use for an OCI image, an interactive development VM, or end-to-end
virtio bootstrap validation. The donate-clanker repository owns the latter.

## Core Process

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
dependency.

The FSDK EFI tree is built separately from this element's root filesystem.
`podman-vm-efi.bst` therefore rewrites each staged loader entry's
`root=UUID=` value from the `prepare-image.sh` output before `genimage`; never
reuse an EFI tree byte-for-byte without checking it against the ext4 root UUID.

`tests/podman-vm.sh` validates the release artifact's checksum, protective MBR,
GPT header, and EFI system partition. It must not use Lima: Lima only reports
an instance as running after SSH comes up, and this guest intentionally does
not ship SSH. End-to-end virtio bootstrap coverage belongs in donate-clanker.

1. Resolve the complete graph with `just validate`.
2. Build and export the artifact with `just export-podman-vm`.
3. Run `tests/podman-vm.sh` against the exported raw disk.
4. Publish only after the artifact-contract test succeeds.

## Common Rationalizations

| Rationalization | Reality |
| --- | --- |
| "Use Lima to prove the guest boots." | Lima waits for SSH; this guest deliberately has no SSH. |
| "The raw disk is just an opaque build output." | The raw GPT disk and its checksum are the release interface and must be validated. |

## Red Flags

- A test assumes cloud-init, SSH, or Podman exists in the guest.
- A release asset is published without its `.sha256` manifest.
- The EFI loader's root UUID is not rewritten after staging.

## Verification

- `BST_LOCAL=1 just bst show --deps all podman-vm/podman-vm-efi.bst`
- `just export-podman-vm` checks out the raw disk and checksum manifest.
- `tests/podman-vm.sh` accepts the exported artifact and verifies its
  checksum-protected GPT/EFI structure.
- Confirm the worker source pin is
  `96cc69f5779d63b908d5f53957287b7ef6bda7fa`.
- Treat the observed x86_64 local benchmark (~10 minutes, 2.2G raw) as
  indicative only, not a contract.
