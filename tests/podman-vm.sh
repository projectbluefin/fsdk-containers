#!/usr/bin/env bash
# tests/podman-vm.sh -- validate a donate-clanker raw GPT/EFI disk artifact.
#
# The guest deliberately contains no SSH, cloud-init, or Podman, so Lima
# cannot observe it as "running". Test the release interface instead: a
# checksum-verified raw GPT disk with an EFI system partition. The
# donate-clanker repository owns end-to-end virtio bootstrap testing.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }

RAW="${1:-${PODMAN_VM_RAW:-}}"
if [ -z "$RAW" ]; then
    shopt -s nullglob
    candidates=("${REPO_ROOT}"/dist-vm/donate-clanker-vm-*.raw)
    shopt -u nullglob
    if [ "${#candidates[@]}" -eq 1 ]; then
        RAW="${candidates[0]}"
    else
        fail "expected exactly one raw disk in dist-vm/ (found ${#candidates[@]}). Run 'just export-podman-vm' first or pass its path explicitly."
    fi
fi

[ -f "$RAW" ] || fail "artifact not found: $RAW"
RAW="$(cd "$(dirname "$RAW")" && pwd)/$(basename "$RAW")"
SUM="${RAW}.sha256"
[ -f "$SUM" ] || fail "checksum manifest not found: $SUM"

printf '==> verifying checksum manifest for %s\n' "$(basename "$RAW")"
( cd "$(dirname "$RAW")" && sha256sum -c "$(basename "$SUM")" )

printf '==> verifying GPT and EFI partition\n'
python3 - "$RAW" <<'PYTHON'
import struct
import sys
import uuid

path = sys.argv[1]
with open(path, "rb") as disk:
    data = disk.read()

if len(data) < 1024:
    raise SystemExit("disk is smaller than a protective MBR and GPT header")
if data[510:512] != b"\x55\xaa":
    raise SystemExit("missing protective MBR signature")

header = data[512:1024]
if header[:8] != b"EFI PART":
    raise SystemExit("missing GPT header signature")

header_size, = struct.unpack_from("<I", header, 12)
current_lba, = struct.unpack_from("<Q", header, 24)
partition_lba, = struct.unpack_from("<Q", header, 72)
partition_count, = struct.unpack_from("<I", header, 80)
partition_size, = struct.unpack_from("<I", header, 84)
if not 92 <= header_size <= 512:
    raise SystemExit(f"invalid GPT header size: {header_size}")
if current_lba != 1:
    raise SystemExit(f"unexpected GPT header LBA: {current_lba}")
if partition_count == 0 or partition_size < 128:
    raise SystemExit("GPT partition table has no standard entries")

table_end = partition_lba * 512 + partition_count * partition_size
if table_end > len(data):
    raise SystemExit("GPT partition table extends beyond disk size")

efi_type = uuid.UUID("c12a7328-f81f-11d2-ba4b-00a0c93ec93b").bytes_le
for index in range(partition_count):
    offset = partition_lba * 512 + index * partition_size
    if data[offset:offset + 16] == efi_type:
        print("EFI system partition found")
        break
else:
    raise SystemExit("GPT has no EFI system partition")
PYTHON

printf 'PASS: %s is a checksum-verified raw GPT/EFI disk\n' "$(basename "$RAW")"
