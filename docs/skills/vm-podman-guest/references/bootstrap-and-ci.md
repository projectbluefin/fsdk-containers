# VM Podman Guest — bootstrap contract and CI

Detail referenced from [`../SKILL.md`](../SKILL.md). Read the skill first.

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

`elements/podman-vm/donate-clanker-vm-config.bst` installs the bootstrap
consumer, its systemd unit, and `/etc/donate-clanker/{worker.source,
goose.yaml, local-agent-policy.md}`, pinned to a `projectbluefin/donate-clanker`
commit. `elements/podman-vm/donate-clanker-worker.bst` compiles
`cmd/contributor` with the FSDK Go toolchain, `CGO_ENABLED=0 GOPROXY=off`, and
a separately pinned `gorilla/websocket` tree wired via a local `go.mod`
replace. The consumer opens the virtio-serial port as an unbuffered binary
stream (virtio ports are non-seekable) and retries until the launcher's
version-2 envelope arrives.

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

The bootstrap additionally exports `DONATE_CLANKER_RUN_ID` (from the
envelope's `run_id`) alongside these.

Exporting `DONATE_CLANKER_*` equivalents instead leaves the worker with no
credentials at all. Check `elements/podman-vm/donate-clanker-worker.bst`'s
pinned ref before changing this table.

Finally, the transport races. QEMU is the chardev *client* of a host-owned
unix socket, so `/dev/virtio-ports/...` may not exist yet when the unit starts,
and a read can return EOF before the launcher has written its line. Both must
be retried; treating either as fatal is what made the whole VM path inert.
Only one process may hold the port open at a time.

## CI pipeline

See [ci-tooling](../../ci-tooling/SKILL.md) for the full workflow structure. In
short, `.github/workflows/vm-guest.yml` is a reusable workflow (called from
`build.yml`) with a per-arch matrix job (x86_64, aarch64) plus an aggregate
`verify-release` job. Each leg
builds the raw disk, converts it to QCOW2, verifies both checksums,
generates the SBOM, boot-tests it under plain QEMU (both architectures, via
`tests/vm-boot.sh`), and
-- only on `push`/`workflow_dispatch` -- compresses the disks and publishes
the compressed disks, checksums, and SBOM as GitHub Release assets, then
attests them (build provenance + SBOM attestation) via `actions/attest` with
`subject-path`. Publish and attestation stay inside the same per-arch job as
steps rather than a separate downstream job, so one architecture's asset is
never stranded behind another architecture's build or test — see
"Independent architecture asset publication" in [ci-tooling](../../ci-tooling/SKILL.md).

`just publish-podman-vm` publishes one architecture's set as an
all-or-nothing transaction, and the `verify-release` job fails the run when
the tag ends up missing any asset for either architecture. See "Atomic
release asset publication" in [ci-tooling](../../ci-tooling/SKILL.md).
