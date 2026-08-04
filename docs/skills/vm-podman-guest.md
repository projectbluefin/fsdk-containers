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
- Confirm the guest also installs the worker's bundled files at
  `/etc/donate-clanker/goose.yaml` and
  `/etc/donate-clanker/local-agent-policy.md`; the worker exits before
  connecting if either file is absent.
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

On Ubuntu GitHub runners, install `ipxe-qemu` with the architecture's QEMU
and UEFI packages: the consumer-compatible `-drive if=virtio` topology makes
QEMU load `efi-virtio.rom`, which that package supplies. Do not replace the
topology just to avoid the package; the boot test must exercise the consumer's
real device layout.

It asserts, in order, that firmware handed off to a bootloader, that the
Linux kernel started, that the initrd switched into the root filesystem,
that the serial getty reached the login prompt, and that systemd activated
`donate-clanker-bootstrap.service`.

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

The bootstrap virtio-serial port is wired anyway, so the guest boots against
the device topology donate-clanker gives it. Nothing is written to it: the
envelope schema belongs to donate-clanker, so a schema bump there must not
turn into a red build here. The bootstrap unit therefore *fails* under the
boot test after its wait expires, which is why the assertion is on activation
(the `/dev/kmsg` banner) and not on success.

There is deliberately **no Lima**. Lima expects cloud-init, an injected SSH
key, a guest agent and its own readiness probe; this guest ships none of
them, so a Lima failure never reliably meant the disk was broken. Do not
reintroduce it.

## Getting diagnostics out of this guest

The guest has no SSH, no guest agent, and no cloud-init. The serial console
is the only channel, and it is narrower than it looks. Measured by booting the
published `donate-clanker-vm-25.08.15-aarch64.raw` under QEMU:

- `systemd` unit output configured as `StandardOutput=journal+console` does
  **not** reach the serial console once `serial-getty@ttyAMA0.service` has run
  its `TTYVHangup=yes`. A marker echoed by such a unit at 90s into the boot was
  visible in `journalctl` and absent from the captured serial log.
- A direct write to `/dev/kmsg` from the same boot **did** land on the serial
  console, timestamped like any kernel message.

So anything a boot test needs to see must go to `/dev/kmsg`. That is why
`donate-clanker-bootstrap.py` mirrors its progress lines there.

## Guest bootstrap contract

`donate-clanker-bootstrap.service` is the only reason this disk exists. It is
enabled by `/usr/lib/systemd/system-preset/01-donate-clanker.preset`, which
FSDK's own `files/vm/prepare-image.sh` applies with
`systemctl --root "${sysroot}" preset-all` while `podman-vm-efi.bst` assembles
the image. The enablement symlink
`/etc/systemd/system/multi-user.target.wants/donate-clanker-bootstrap.service`
is therefore baked into the published disk -- verified with `debugfs` against
`donate-clanker-vm-25.08.15-aarch64.raw`. Do not add a second enablement
mechanism; there is nothing to fix there.

`/usr/libexec/donate-clanker-bootstrap` sits between two schemas, and it has to
match **both** or the VM boots to an idle login prompt:

| End | Source of truth |
| --- | --------------- |
| Envelope in | donate-clanker's `just/61-donate-clanker.just` bootstrap server |
| Environment out | donate-clanker's `cmd/contributor` + `internal/hive` |

The envelope is protocol **version 2**: required `hive_endpoint`,
`registration_token`, `backend`, `run_id`; optional `goose_provider`,
`goose_model`, `provider_secret`. Validate the required keys and ignore
unknown ones -- an exact key-set comparison rejects every real envelope the
moment donate-clanker adds an optional field. The acknowledgement must be
`{"version": 2, "type": "control_ack"}`; the launcher aborts on anything else.

The worker reads its Hive credentials from the environment *first*, using
these names and no others:

```text
HIVE_WS_URL / HIVE_HUB     <- hive_endpoint
HIVE_REGISTRATION_TOKEN    <- registration_token
AGENT_BACKEND              <- backend
GOOSE_PROVIDER             <- goose_provider (default: github_copilot)
GOOSE_MODEL                <- goose_model
GITHUB_COPILOT_TOKEN       <- provider_secret
```

Exporting `DONATE_CLANKER_*` equivalents instead leaves the worker with no
credentials at all. Check `elements/podman-vm/donate-clanker-worker.bst`'s
pinned ref before changing this table.

Finally, the transport races. QEMU is the chardev *client* of a host-owned
unix socket, so `/dev/virtio-ports/...` may not exist yet when the unit starts,
and a read can return EOF before the launcher has written its line. Both must
be retried; treating either as fatal is what made the whole VM path inert.
Only one process may hold the port open at a time.

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
