#!/usr/bin/env bash
# tests/vm-boot.sh -- QEMU boot test for the donate-clanker VM guest disk.
#
# Boots a supplied raw disk exactly the way the only real consumer boots it:
# projectbluefin/donate-clanker's `just/61-donate-clanker.just`. That means
# plain `qemu-system-<arch>`, EDK2/OVMF firmware as a `-drive if=pflash`
# pair (with a single-blob `-bios` fallback), a per-run QCOW2 overlay backed
# by the raw disk, user-mode virtio networking, and the virtio-serial
# bootstrap port the guest's own `donate-clanker-bootstrap.service` opens.
#
# It does NOT use Lima, cloud-init, SSH or Podman. The guest ships none of
# them (see docs/skills/vm-podman-guest.md), so a harness that expects them
# reports failures the disk is not responsible for.
#
# The test asserts on the serial console, in order:
#   1. firmware handed off to a bootloader,
#   2. the Linux kernel started,
#   3. the initrd found the root filesystem by UUID and switched into it,
#   4. the guest reached its ready point: systemd started the serial getty
#      and the console shows the login prompt.
#
# Marker 3 is the one that catches the failure mode this guest actually has.
# The loader entry's `root=UUID=` and the ext4 root UUID are generated in two
# different BuildStream builds (see elements/podman-vm/podman-vm-efi.bst);
# when they disagree the initrd sits on "Expecting device
# dev-disk-by-uuid-..." forever and never switches root. Marker 4 then proves
# the real root userspace came up: PID 1 mounted the ext4 the build produced,
# reached multi-user.target, and spawned a getty on the serial console.
#
# These are markers this image genuinely emits, verified by booting the
# published donate-clanker-vm-25.08.15-aarch64.raw. Note what is deliberately
# NOT asserted: donate-clanker-bootstrap.service. The unit and its
# `enable` preset ship in the image, but the preset is not applied at
# runtime, so the unit never starts and asserting on it would fail every
# build for a reason no disk build can fix.
#
# Nothing here is a skip. A missing artifact, a bad checksum, missing
# tooling, missing firmware, a boot timeout or a missing marker are all hard
# failures, and the captured serial log is printed into the job output so
# the next failure is debuggable without downloading an artifact.
#
# Usage:
#   tests/vm-boot.sh [path/to/donate-clanker-vm-<version>-<arch>.raw]
#
# Env overrides:
#   PODMAN_VM_RAW           same as the positional argument
#   PODMAN_VM_BOOT_TIMEOUT  seconds to wait for the ready marker
#                           (default: 300 with KVM, 1800 under TCG)
#   PODMAN_VM_SKIP_CHECKSUM set to 1 only for the negative tests that
#                           deliberately feed this script a broken disk
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LOG_DIR="${REPO_ROOT}/tests/artifacts"

log() { printf '==> %s\n' "$*" >&2; }
fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }

# 1. Resolve the artifact --------------------------------------------------
RAW="${1:-${PODMAN_VM_RAW:-}}"
if [ -z "$RAW" ]; then
    shopt -s nullglob
    candidates=("${REPO_ROOT}"/dist-vm/donate-clanker-vm-*.raw)
    shopt -u nullglob
    if [ "${#candidates[@]}" -eq 1 ]; then
        RAW="${candidates[0]}"
    else
        fail "no raw disk supplied and dist-vm/ does not contain exactly one (found ${#candidates[@]}). Build one with 'just export-podman-vm', or pass the path: tests/vm-boot.sh /path/to/donate-clanker-vm-<version>-<arch>.raw"
    fi
fi
[ -f "$RAW" ] || fail "artifact not found: $RAW -- this test never treats a missing artifact as a pass"
RAW="$(cd "$(dirname "$RAW")" && pwd)/$(basename "$RAW")"

# The architecture is carried by the artifact name, not by the host: the
# harness must refuse to boot an aarch64 disk with qemu-system-x86_64.
case "$(basename "$RAW")" in
    *-x86_64.raw)  ARCH=x86_64 ;;
    *-aarch64.raw) ARCH=aarch64 ;;
    *) fail "cannot derive the architecture from $(basename "$RAW") -- expected donate-clanker-vm-<version>-<x86_64|aarch64>.raw" ;;
esac

# 2. Verify integrity before booting anything ------------------------------
if [ "${PODMAN_VM_SKIP_CHECKSUM:-}" = 1 ]; then
    log "WARNING: checksum verification disabled (PODMAN_VM_SKIP_CHECKSUM=1)"
else
    SUM="${RAW}.sha256"
    [ -f "$SUM" ] || fail "checksum manifest not found: $SUM -- every published VM disk ships a 'sha256sum --binary' manifest beside it"
    # The manifest names the file it covers, and `sha256sum -c` checks that
    # name, not the path passed in. Without this, a manifest left over from a
    # different disk in the same directory would be "verified" while the disk
    # under test was never hashed at all.
    grep -qE "[[:space:]][ *]?$(basename "$RAW")\$" "$SUM" \
        || fail "checksum manifest $(basename "$SUM") does not cover $(basename "$RAW")"
    log "verifying checksum manifest for $(basename "$RAW")"
    ( cd "$(dirname "$RAW")" && sha256sum -c "$(basename "$SUM")" ) \
        || fail "checksum mismatch -- artifact is corrupt or was tampered with, refusing to boot it"
    log "OK: checksum verified"
fi

# 3. Preflight tooling -----------------------------------------------------
QEMU="qemu-system-${ARCH}"
command -v "$QEMU" >/dev/null 2>&1 \
    || fail "${QEMU} not found in PATH -- install it (Debian/Ubuntu: qemu-system-x86 / qemu-system-arm)"
command -v qemu-img >/dev/null 2>&1 \
    || fail "qemu-img not found in PATH -- required to create the QCOW2 overlay (Debian/Ubuntu: qemu-utils)"

HOST_ARCH="$(uname -m)"
ACCEL=tcg
if [ "$ARCH" = "$HOST_ARCH" ] && [ -r /dev/kvm ] && [ -w /dev/kvm ]; then
    ACCEL=kvm
fi
if [ "$ACCEL" = kvm ]; then
    log "acceleration: KVM (${ARCH} on ${HOST_ARCH})"
    DEFAULT_TIMEOUT=300
else
    log "acceleration: TCG software emulation (${ARCH} on ${HOST_ARCH}) -- boot will be slow"
    DEFAULT_TIMEOUT=1800
fi
BOOT_TIMEOUT="${PODMAN_VM_BOOT_TIMEOUT:-$DEFAULT_TIMEOUT}"

# 4. Locate EDK2/OVMF firmware ---------------------------------------------
# Same two naming schemes donate-clanker searches for: distro packages use
# OVMF_CODE*.fd / AAVMF_CODE.fd, QEMU's own bundled firmware uses
# edk2-<arch>-code.fd.
case "$ARCH" in
    x86_64)  FW_NAMES=(edk2-x86_64-code.fd OVMF_CODE.fd OVMF_CODE_4M.fd OVMF.fd) ;;
    aarch64) FW_NAMES=(edk2-aarch64-code.fd AAVMF_CODE.fd QEMU_EFI.fd) ;;
esac
FW_ROOTS=("$(dirname "$(dirname "$(command -v "$QEMU")")")/share/qemu" /usr/share /usr/lib)
FIRMWARE=""
for dir in "${FW_ROOTS[@]}"; do
    [ -d "$dir" ] || continue
    for name in "${FW_NAMES[@]}"; do
        # -L because Homebrew symlinks share/qemu into ../Cellar/qemu/<v>/.
        found="$(find -L "$dir" -name "$name" -print -quit 2>/dev/null || true)"
        [ -n "$found" ] && { FIRMWARE="$found"; break 2; }
    done
done
[ -n "$FIRMWARE" ] || fail "no UEFI firmware for ${ARCH} found in ${FW_ROOTS[*]} (looked for: ${FW_NAMES[*]}) -- install it (Debian/Ubuntu: ovmf / qemu-efi-aarch64)"
log "firmware: ${FIRMWARE}"

firmware_vars() {
    local dir base vars
    dir="$(dirname "$1")"; base="$(basename "$1")"
    case "$base" in
        edk2-x86_64-code.fd|edk2-i386-code.fd|edk2-x86_64-secure-code.fd) vars=edk2-i386-vars.fd ;;
        edk2-aarch64-code.fd|edk2-arm-code.fd)                            vars=edk2-arm-vars.fd ;;
        OVMF_CODE.fd|OVMF_CODE_4M.fd)                                     vars=OVMF_VARS.fd ;;
        AAVMF_CODE.fd)                                                    vars=AAVMF_VARS.fd ;;
        *) return 1 ;;
    esac
    [ -f "${dir}/${vars}" ] && { printf '%s\n' "${dir}/${vars}"; return 0; }
    [ "$vars" = OVMF_VARS.fd ] && [ -f "${dir}/OVMF_VARS_4M.fd" ] \
        && { printf '%s\n' "${dir}/OVMF_VARS_4M.fd"; return 0; }
    return 1
}

# 5. Per-run working directory ---------------------------------------------
WORKDIR="$(mktemp -d -t vm-boot-test.XXXXXX)"
SERIAL_LOG="${WORKDIR}/serial.log"
OVERLAY="${WORKDIR}/overlay.qcow2"
QEMU_PID=""

cleanup() {
    local exit_code=$?
    [ -n "$QEMU_PID" ] && kill "$QEMU_PID" 2>/dev/null || true
    [ -n "$QEMU_PID" ] && wait "$QEMU_PID" 2>/dev/null || true
    mkdir -p "$LOG_DIR"
    cp -f "$SERIAL_LOG" "${LOG_DIR}/serial.log" 2>/dev/null || true
    if [ "$exit_code" -ne 0 ]; then
        printf '\n===== captured serial console (%s) =====\n' "$(basename "$RAW")" >&2
        cat "$SERIAL_LOG" >&2 2>/dev/null || echo "(serial log is empty -- QEMU produced no console output at all)" >&2
        printf '===== end of serial console =====\n\n' >&2
        log "serial log preserved at ${LOG_DIR}/serial.log"
    fi
    rm -rf "$WORKDIR"
    exit "$exit_code"
}
trap cleanup EXIT INT TERM

# 6. Boot a disposable QCOW2 overlay, NEVER the master raw disk ------------
# donate-clanker does exactly this, for exactly this reason: writing to the
# master mutates it and breaks its published checksum. The overlay dies with
# the run, and step 9 re-verifies the master to prove it stayed pristine.
qemu-img create -q -f qcow2 -F raw -b "$RAW" "$OVERLAY" \
    || fail "could not create the QCOW2 overlay over $(basename "$RAW")"
log "created QCOW2 overlay over the raw disk (the master is never booted directly)"

case "$ARCH" in
    x86_64)  MACHINE=q35; SERIAL_DEVICE=virtio-serial-pci ;;
    aarch64) MACHINE=virt; SERIAL_DEVICE=virtio-serial-device ;;
esac
if [ "$ACCEL" = kvm ]; then
    ACCEL_ARGS=(-enable-kvm -machine "$MACHINE" -cpu host)
else
    ACCEL_ARGS=(-machine "$MACHINE" -cpu max)
fi

FIRMWARE_ARGS=()
if VARS_TEMPLATE="$(firmware_vars "$FIRMWARE")"; then
    RUN_VARS="${WORKDIR}/efivars.fd"
    cp -f "$VARS_TEMPLATE" "$RUN_VARS"
    chmod u+w "$RUN_VARS"
    FIRMWARE_ARGS=(
        -drive "if=pflash,format=raw,unit=0,readonly=on,file=${FIRMWARE}"
        -drive "if=pflash,format=raw,unit=1,file=${RUN_VARS}"
    )
else
    FIRMWARE_ARGS=(-bios "$FIRMWARE")
fi

# The bootstrap virtio-serial port is wired so the guest boots against the
# same device topology donate-clanker gives it, and so that the port exists
# if donate-clanker-bootstrap.service is ever actually enabled at runtime.
# Nothing is written to it: the envelope schema belongs to donate-clanker, so
# a schema bump there must not turn into a red build here.
BOOTSTRAP_SOCKET="${WORKDIR}/bootstrap.sock"

log "booting ${ARCH} guest headless (timeout ${BOOT_TIMEOUT}s), serial captured to ${SERIAL_LOG}"
: > "$SERIAL_LOG"
"$QEMU" \
    "${ACCEL_ARGS[@]}" -smp 2 -m 2048 \
    "${FIRMWARE_ARGS[@]}" \
    -drive "file=${OVERLAY},format=qcow2,if=virtio" \
    -nic user,model=virtio \
    -chardev "socket,id=control,path=${BOOTSTRAP_SOCKET},server=on,wait=off" \
    -device "$SERIAL_DEVICE" \
    -device "virtserialport,chardev=control,name=org.projectbluefin.donate-clanker.bootstrap" \
    -display none -serial "file:${SERIAL_LOG}" -monitor none &
QEMU_PID=$!

# 7. Wait for the ready marker --------------------------------------------
# The login prompt the serial getty writes once multi-user.target is up.
READY_PATTERN='[[:alnum:]][[:alnum:]_.-]* login:'
deadline=$(( $(date +%s) + BOOT_TIMEOUT ))
ready=0
while [ "$(date +%s)" -lt "$deadline" ]; do
    if grep -qaE "$READY_PATTERN" "$SERIAL_LOG" 2>/dev/null; then
        ready=1
        break
    fi
    if ! kill -0 "$QEMU_PID" 2>/dev/null; then
        fail "QEMU exited before the guest reached its ready point"
    fi
    sleep 2
done
[ "$ready" -eq 1 ] || fail "guest did not reach its ready point within ${BOOT_TIMEOUT}s (no serial login prompt on the console)"

# 8. Assert the whole chain, in order --------------------------------------
assert_serial() {
    local what="$1" pattern="$2" hit
    hit="$(grep -m1 -aiE "$pattern" "$SERIAL_LOG" || true)"
    [ -n "$hit" ] || fail "${what}: no line matching /${pattern}/ on the serial console"
    log "OK: ${what} -- $(printf '%s' "$hit" | tr -d '\r' | cut -c1-120)"
}
assert_serial "firmware handed off to a bootloader" \
    'BdsDxe: starting Boot|systemd-boot|EFI stub'
assert_serial "the Linux kernel started" \
    'Linux version [0-9]'
assert_serial "the initrd switched into the root filesystem" \
    'initrd-switch-root|Switching root'
assert_serial "the serial getty reached the login prompt" \
    "$READY_PATTERN"

# 9. Prove the master raw disk was not written to --------------------------
kill "$QEMU_PID" 2>/dev/null || true
wait "$QEMU_PID" 2>/dev/null || true
QEMU_PID=""
if [ "${PODMAN_VM_SKIP_CHECKSUM:-}" != 1 ]; then
    ( cd "$(dirname "$RAW")" && sha256sum -c "$(basename "${RAW}.sha256")" ) \
        || fail "the master raw disk changed during the boot -- the QCOW2 overlay did not protect it"
    log "OK: master raw disk is byte-identical after the boot"
fi

log "PASS: $(basename "$RAW") boots under plain QEMU the way donate-clanker boots it"
