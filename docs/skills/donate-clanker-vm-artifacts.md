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

The guest includes FSDK's minimal systemd/linux/dracut userspace, networking,
DNS/certificates, git, the pinned worker, `/sbin/init`, empty machine-id, and
the EFI system partition. It does not include Podman, SSH, or cloud-init. The final
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

`podman-vm/donate-clanker-vm-config.bst` installs the guest bootstrap consumer,
systemd unit, and `/etc/donate-clanker/worker.source`, pinned to
`projectbluefin/donate-clanker` commit
`7f16610ead3d82826ca4f662a7c1d1624415f43a`. The consumer reads the
virtio-serial envelope, validates it, sends `control_ack`, keeps credentials in
memory, and execs `/usr/libexec/donate-clanker-worker`.

`podman-vm/donate-clanker-worker.bst` compiles `cmd/contributor` with the FSDK
Go toolchain, `CGO_ENABLED=0`, `GOPROXY=off`, and a separately pinned
`gorilla/websocket` source tree wired with a local `go.mod` replacement. The
source commit is not yet published on GitHub, so BuildStream currently fails
at source fetch with `...7f16610... not found in remote`; publish that commit
before enabling remote builds. No binary or digest is fabricated.

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
- [ ] The worker input is supplied at `/usr/libexec/donate-clanker-worker`.
- [ ] `podman-vm/donate-clanker-worker.bst` builds after the pinned source is
      published.
