---
name: donate-clanker-vm-artifacts
description: Build the bootable donate-clanker VM guest from the FSDK VM graph.
metadata:
  context7-sources:
    - /apache/buildstream
    - /python/cpython
---

# Donate-clanker VM artifacts

## When to Use

Use for the bootable guest disk artifact consumed by donate-clanker. The target
is `podman-vm/podman-vm-efi.bst`; it is a raw GPT/EFI disk, not an OCI image.

## When NOT to Use

Do not use for the host launcher, QEMU runner container, or release validation
in `donate-clanker`.

## Core Process

The target reuses the FSDK VM graph:

`vm/minimal/deps.bst` → `podman-vm/podman-vm-deps.bst` →
`podman-vm/podman-vm-filesystem.bst` → `podman-vm/podman-vm-efi.bst`.

The guest is the full FSDK VM/uutils base plus networking, certificates, git,
the pinned worker, `/sbin/init`, an empty machine-id, and the EFI system
partition. It does not include Podman, SSH, cloud-init, or `qemu-img`. The final
install-root contains exactly:

```text
donate-clanker-vm-<fsdk-version>-<arch>.raw
donate-clanker-vm-<fsdk-version>-<arch>.raw.sha256
```

`podman-vm/podman-vm-efi.bst` assembles the full rootfs plus EFI tree with
`genimage` and copies the resulting raw GPT disk to the install root. QEMU
boots the raw disk directly.

`podman-vm/donate-clanker-vm-config.bst` installs the guest bootstrap consumer,
systemd unit, and `/etc/donate-clanker/worker.source`, pinned to
`projectbluefin/donate-clanker` commit
`96cc69f5779d63b908d5f53957287b7ef6bda7fa`. The consumer opens the
virtio-serial channel as an unbuffered binary stream because virtio ports are
non-seekable; it decodes the envelope line, validates it, encodes
`control_ack`, keeps credentials in memory, and execs
`/usr/libexec/donate-clanker-worker`.

The EFI tree is staged separately from the root filesystem. Before `genimage`
copies it into the disk, `podman-vm-efi.bst` rewrites each loader entry's
`root=UUID=` to the UUID emitted by the same `prepare-image.sh` invocation that
creates the ext4 root filesystem.

`podman-vm/donate-clanker-worker.bst` compiles `cmd/contributor` with the FSDK
Go toolchain, `CGO_ENABLED=0`, `GOPROXY=off`, and a separately pinned
`gorilla/websocket` source tree wired with a local `go.mod` replacement.

An observed x86_64 local build took approximately 10 minutes and produced a
2.2G raw disk. This is a local benchmark, not a size or duration guarantee.

## Common Rationalizations

| Rationalization | Reality |
|---|---|
| "Publish qemu-img as the guest." | `qemu-img` is not in this VM; publish the raw disk assembled by `vm/prepare-image.bst` and `genimage`. |
| "Use an OCI rootfs instead." | The launcher consumes a filesystem image with EFI/kernel boot content, not an OCI layer. |

## Red Flags

- The requested target is an OCI `qemu-system` or `qemu-img` image.
- `vm/minimal/deps.bst` and `vm/boot/efi.bst` are bypassed.
- The output lacks both the raw disk and binary checksum manifest.
- A Lima test is used to prove this guest booted. Lima requires SSH, which the
  guest deliberately excludes.

## Verification

- [ ] `BST_LOCAL=1 just bst show --deps all podman-vm/podman-vm-efi.bst`
- [ ] `just export-podman-vm` checks out only the raw disk and `.sha256`.
- [ ] `tests/podman-vm.sh` verifies the exported artifact's checksum and
      GPT/EFI structure without requiring SSH.
- [ ] The dependency graph contains no Podman, SSH, cloud-init, or `qemu-img`.
- [ ] The worker input is supplied at `/usr/libexec/donate-clanker-worker`.
- [ ] `podman-vm/donate-clanker-worker.bst` builds from the pinned source.
