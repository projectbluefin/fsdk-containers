---
name: donate-clanker-vm-artifacts
description: Build and publish the donate-clanker QEMU runner and guest rootfs first slice.
metadata:
  context7-sources:
    - /apache/buildstream
---

# Donate-clanker VM artifacts

## When to Use

Use when adding or changing the donate-clanker QEMU runner or guest artifact
targets in `fsdk-containers`.

## When NOT to Use

Do not use for launcher, guest bootstrap, or release-gate changes in
`donate-clanker`; those belong to that repository.

## Core Process

The producer publishes two multi-architecture OCI images:

- `donate-clanker-vm-runner`: a headless, host-architecture QEMU system emulator
  with KVM support. The launcher invokes `qemu-system-x86_64` on amd64 and
  `qemu-system-aarch64` on arm64.
- `donate-clanker-guest`: an FSDK runtime rootfs carrying
  `/etc/donate-clanker/guest-artifact.json`.

The guest image is intentionally the first slice of the contract. Its manifest
declares `format=donate-clanker-guest-rootfs-v1`, `rootfs=/`, and that kernel
and initramfs are external inputs. It does not invent references for those
inputs; a later guest-kernel producer must publish them as separate immutable
artifacts before the full VM release gate can pass.

Both images use the normal FSDK release tag matrix, BuildStream-native SBOM,
keyless Cosign signature, and GitHub provenance attestation. Validate the graph
with `just validate`; build and inspect a target with
`BUILD_IMAGE_NAME=donate-clanker-vm-runner just build` and `just verify`.

## Common Rationalizations

| Rationalization | Reality |
|---|---|
| "A qemu-img image is close enough." | The launcher requires a QEMU system emulator with microVM support. |
| "Use placeholder artifact digests for the missing boot payload." | Never publish fake references; keep kernel/initramfs explicitly external. |

## Red Flags

- The runner target contains `qemu-img` instead of `qemu-system-*`.
- Kernel or initramfs references are invented in this repository.
- A new target is missing from validation, SBOM, or both architecture matrices.

## Verification

- [ ] `BST_LOCAL=1 just bst show --deps all oci/donate-clanker-vm-runner.bst oci/donate-clanker-guest.bst`
- [ ] `git diff --check`
- [ ] `just test-tags`
- [ ] Both targets are present in the build and manifest matrices.
