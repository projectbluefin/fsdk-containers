---
name: vm-podman-guest
version: "1.1"
last_updated: 2026-09-18
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
published set per architecture is exactly 7 assets (14 total across both
architectures `x86_64` and `aarch64` for a given point-release tag `v<fsdk-version>`):

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
This is the shape downstream consumers (`projectbluefin/donate-clanker`,
and planned consumer `projectbluefin/review`) fetch: download `.raw.zst`, decompress, then
`sha256sum -c` the `.raw.sha256` sidecar. Do not rename these assets without
changing the launcher.

#### Authenticity vs. Integrity Verification

Downstream consumers must distinguish download integrity from authenticity:
- **Integrity:** Verified via the accompanying `.sha256` sidecars (`sha256sum -c`).
  This proves the downloaded archive or decompressed image has not suffered
  transport corruption, but provides **zero authenticity** on its own (a compromised
  release could replace both asset and checksum).
- **Authenticity & Provenance:** Provided by GitHub Artifact Attestations
  (`actions/attest`). Because disk images have no OCI registry, attestations are stored
  in GitHub's attestation authority (`push-to-registry: false`). Consumers verify
  downloaded artifacts using the GitHub CLI:

```bash
gh attestation verify donate-clanker-vm-<fsdk-version>-<arch>.raw.zst \
  -R projectbluefin/fsdk-containers \
  --signer-repo projectbluefin/fsdk-containers
```

Note: `actions/attest` attests the local raw and QCOW2 disks as well as their
compressed `.zst` equivalents, but only the `.zst` files, checksum manifests,
and SPDX SBOMs are uploaded as release assets due to GitHub's per-asset size limit.

### Transaction semantics (`publish-podman-vm`)

`just publish-podman-vm` uploads one architecture's asset set as an all-or-nothing
transaction with explicit safety guarantees:

- **Preflight:** Validates that every file in the architecture's set exists in `dist-vm/`
  and is strictly under GitHub's 2 GiB per-asset limit (`LIMIT=2147483648`) before
  any network upload begins. An oversized asset fails immediately rather than mid-upload.
- **Repair:** Inspects existing release assets for tag `v<fsdk-version>`. If a release
  carries only PART of this architecture's set (debris of an earlier interrupted or
  failed publish run), the orphan assets are deleted before republishing the complete set.
- **Immutability:** If all expected assets for this architecture already exist on the
  release tag, the publish step exits with status 0 without re-uploading (`complete
  point-release asset set already published, immutable`). Complete sets are never
  overwritten.
- **Rollback:** Maintains an `uploaded=()` list and an ERR trap (`rollback()`). If any
  upload or verification step fails, all assets uploaded during that invocation are
  deleted from the release so a failed run never leaves orphan checksums or disks.
  A cancelled run (SIGINT/SIGTERM) does not fire the ERR trap; the Repair step above
  is what clears that debris on the next publish.
- **Post-verify:** Re-reads the release asset inventory after upload and asserts that
  every expected asset is present with its expected byte size. Any mismatch triggers
  rollback and exits non-zero.
- **Aggregate Verification (`verify-release`):** In CI (`.github/workflows/vm-guest.yml`),
  each architecture publishes independently so one architecture's build or test never
  strands the other. A downstream `verify-release` job runs after both architecture legs
  complete, failing if the point-release tag is missing any of the 14 assets across
  both `x86_64` and `aarch64`.

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

- `just bst show --deps all podman-vm/podman-vm-efi.bst`
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
