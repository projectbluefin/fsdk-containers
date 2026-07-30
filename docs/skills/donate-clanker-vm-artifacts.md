---
name: donate-clanker-vm-artifacts
description: Build the bootable donate-clanker VM guest from the FSDK VM graph.
metadata:
  context7-sources:
    - /apache/buildstream
---

# Donate-clanker VM artifacts

## When to Use

Use for the bootable guest disk artifact consumed by donate-clanker. The target
is `podman-vm/podman-vm-efi.bst`; it is a QCOW2/EFI disk, not an OCI image.

## When NOT to Use

Do not use for the host launcher, QEMU runner container, or release validation
in `donate-clanker`.

## Core Process

The target reuses the FSDK VM graph:

`vm/minimal/deps.bst` → `podman-vm/podman-vm-deps.bst` →
`podman-vm/podman-vm-filesystem.bst` → `podman-vm/podman-vm-efi.bst`.

The guest includes the full systemd/linux/dracut userspace, networking, SSH,
cloud-init, Podman runtime, and the EFI system partition. The final
install-root contains exactly:

```text
podman-vm-<fsdk-version>-<arch>.qcow2
podman-vm-<fsdk-version>-<arch>.qcow2.sha256
```

`qemu-img/qemu-img.bst` is used only as the conversion tool from the generated
raw GPT disk to QCOW2; it is not the VM artifact.

## Common Rationalizations

| Rationalization | Reality |
|---|---|
| "Publish qemu-img as the guest." | The guest must be a bootable disk assembled by `vm/prepare-image.bst` and `genimage`. |
| "Use an OCI rootfs instead." | The launcher consumes a filesystem image with EFI/kernel boot content, not an OCI layer. |

## Red Flags

- The requested target is an OCI `qemu-system` or `qemu-img` image.
- `vm/minimal/deps.bst` and `vm/boot/efi.bst` are bypassed.
- The output lacks both the QCOW2 and binary checksum manifest.

## Verification

- [ ] `BST_LOCAL=1 just bst show --deps all podman-vm/podman-vm-efi.bst`
- [ ] `just export-podman-vm` checks out only the QCOW2 and `.sha256`.
- [ ] `qemu-img` appears only as a build-time conversion dependency.
