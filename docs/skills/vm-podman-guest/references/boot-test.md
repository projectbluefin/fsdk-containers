# VM Podman Guest — boot test and diagnostics

Detail referenced from [`../SKILL.md`](../SKILL.md). Read the skill first.

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
mode. The boot cmdline's `root=UUID=` and the ext4 root UUID come from two
different BuildStream builds; when they disagree the initrd waits on
`Expecting device dev-disk-by-uuid-...` forever. Observed on the published
`donate-clanker-vm-25.08.14-x86_64.raw` (built before the loader-entry
rewrite in `podman-vm-efi.bst` landed): loader entry
`root=UUID=9e71ad99-5ddc-5b20-8b9c-f3f6b4e570e1`, actual ext4 root UUID
`a5e5b74b-7aa6-58b1-8408-e4147a36da17`. The same mismatch returned when FSDK
26.08 moved the cmdline from loader entries into the UKI's `.cmdline` section
(plus an upstream-added `quiet` that hid every boot message from the serial
log): the 25.08-era rewrite loop found no entries, silently did nothing, and
the initrd waited on FSDK's namespace UUID forever. `podman-vm-efi.bst` now
patches whichever layout is staged and fails the build if it finds neither.
The login prompt then proves the real root userspace came up. On failure the captured serial log is printed
to stderr and uploaded as an artifact by the composite action, so a CI failure
is diagnosable without downloading anything.

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
