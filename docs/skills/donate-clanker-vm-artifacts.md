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
cloud-init, Podman runtime, `/sbin/init`, empty machine-id, and the EFI system
partition. The final
install-root contains exactly:

```text
donate-clanker-vm-<fsdk-version>-<arch>.qcow2
donate-clanker-vm-<fsdk-version>-<arch>.qcow2.sha256
```

`qemu-img/qemu-img.bst` is used only as the conversion tool from the generated
raw GPT disk to QCOW2; it is not the VM artifact.

BuildStream element outputs are filesystem trees, not disk images. Therefore
`podman-vm/podman-vm-efi.bst` assembles the full rootfs plus EFI tree with
`genimage`, then converts the raw GPT image to QCOW2.

The remaining producer input is the donate-clanker guest worker executable and
its Goose/runtime payload. The current donate-clanker repository has no
guest-specific binary or vendored Go dependency payload that this repository
can build hermetically, so the VM target does not claim that worker is present.

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
