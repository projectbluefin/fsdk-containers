#!/usr/bin/env bash
# tests/podman-vm.sh -- QEMU/Lima integration test for the podman-vm guest.
#
# Boots a checked-out/downloaded podman-vm raw artifact under Lima's QEMU
# driver in "plain" mode (see docs/skills/vm-podman-guest.md), verifies
# Cloud-init created the Lima user with the injected SSH key and host UID,
# then runs a rootless `podman run` smoke image inside the guest.
#
# This test NEVER claims a successful boot when the artifact cannot be
# built/found: a missing artifact, checksum mismatch, missing tooling, boot
# timeout, or provisioning failure are all hard failures with diagnostics --
# never a silent skip or a false pass. It tests a *supplied* artifact; it
# does not build one itself (see `just export-podman-vm`).
#
# Usage:
#   tests/podman-vm.sh [path/to/donate-clanker-vm-<version>-<arch>.raw]
#
# The QCOW2's sibling "<file>.sha256" (a `sha256sum --binary` manifest, as
# produced by elements/podman-vm/podman-vm-efi.bst) must sit next to it and
# is verified before boot.
#
# Env overrides:
#   PODMAN_VM_QCOW2         same as the positional argument
#   PODMAN_VM_SMOKE_IMAGE   image for the in-guest `podman run` smoke test
#                           (default: docker.io/library/busybox:latest)
#   PODMAN_VM_BOOT_TIMEOUT  seconds to wait for boot + Cloud-init (default: 300)
#   LIMA_INSTANCE_NAME      override the generated Lima instance name
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LOG_DIR="${REPO_ROOT}/tests/artifacts"
SMOKE_IMAGE="${PODMAN_VM_SMOKE_IMAGE:-docker.io/library/busybox:latest}"
BOOT_TIMEOUT="${PODMAN_VM_BOOT_TIMEOUT:-300}"

log() { printf '==> %s\n' "$*" >&2; }
fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }

# 1. Resolve the artifact ----------------------------------------------
RAW="${1:-${PODMAN_VM_RAW:-}}"
if [ -z "$RAW" ]; then
    shopt -s nullglob
    candidates=("${REPO_ROOT}"/dist-vm/donate-clanker-vm-*.raw)
    shopt -u nullglob
    if [ "${#candidates[@]}" -eq 1 ]; then
        RAW="${candidates[0]}"
    else
        fail "no QCOW2 artifact supplied and dist-vm/ does not contain exactly one (found ${#candidates[@]}). Build one first with 'just export-podman-vm', or pass the path explicitly: tests/podman-vm.sh /path/to/podman-vm-<version>-<arch>.qcow2"
    fi
fi
[ -f "$RAW" ] || fail "artifact not found: $RAW -- this test never treats a missing artifact as a pass"
RAW="$(cd "$(dirname "$RAW")" && pwd)/$(basename "$RAW")"
SUM="${RAW}.sha256"
[ -f "$SUM" ] || fail "checksum manifest not found: $SUM -- every published podman-vm artifact ships a 'sha256sum --binary' manifest beside it"

# 2. Verify integrity (catches download corruption) ---------------------
log "verifying checksum manifest for $(basename "$RAW")"
if ! ( cd "$(dirname "$RAW")" && sha256sum -c "$(basename "$SUM")" ); then
    fail "checksum mismatch -- artifact is corrupt or was tampered with, refusing to boot it"
fi
log "OK: checksum verified"

# 3. Preflight tooling ----------------------------------------------------
command -v limactl >/dev/null 2>&1 || fail "limactl not found in PATH -- install Lima (https://lima-vm.io) before running this test"
HOST_ARCH="$(uname -m)"
log "host arch: ${HOST_ARCH}, $(limactl --version 2>&1 | head -1)"
if [ -e /dev/kvm ]; then
    log "OK: /dev/kvm present (hardware acceleration available)"
else
    log "WARNING: /dev/kvm not present -- QEMU will fall back to TCG software emulation (much slower boot; raise PODMAN_VM_BOOT_TIMEOUT if this times out)"
fi

# 4. Prepare an isolated Lima instance ------------------------------------
INSTANCE="${LIMA_INSTANCE_NAME:-podman-vm-test-$$}"
# Deliberately NOT nested under REPO_ROOT: Lima's per-instance SSH control
# socket path (LIMA_HOME/<instance>/ssh.sock.<port>) must stay under
# UNIX_PATH_MAX (108 bytes on Linux). A repo checkout nested several
# directories deep (e.g. CI runner work dirs, this project's own worktree
# layout) plus an instance name easily blows that budget -- confirmed by
# reproducing `limactl start` failing with "... must be less than
# UNIX_PATH_MAX=108 characters" when LIMA_HOME was placed under
# "${REPO_ROOT}/.cache". The system temp dir keeps this short and portable.
WORKDIR="$(mktemp -d -t podman-vm-test.XXXXXX)"
PRESERVED_LOGS="${LOG_DIR}/${INSTANCE}"

cleanup() {
    local exit_code=$?
    mkdir -p "$PRESERVED_LOGS"
    log "collecting guest logs for ${INSTANCE} (preserved at ${PRESERVED_LOGS})"
    cp -f "${WORKDIR}/${INSTANCE}"/serial*.log "$PRESERVED_LOGS"/ 2>/dev/null || true
    cp -f "${WORKDIR}/${INSTANCE}"/ha.stderr.log "$PRESERVED_LOGS"/ 2>/dev/null || true
    LIMA_HOME="$WORKDIR" limactl shell "$INSTANCE" -- sudo journalctl --no-pager -u cloud-init -u cloud-final \
        > "${PRESERVED_LOGS}/cloud-init.journal.log" 2>/dev/null || true
    LIMA_HOME="$WORKDIR" limactl stop -f "$INSTANCE" >/dev/null 2>&1 || true
    LIMA_HOME="$WORKDIR" limactl delete -f "$INSTANCE" >/dev/null 2>&1 || true
    rm -rf "$WORKDIR"
    if [ "$exit_code" -ne 0 ]; then
        log "FAILED -- guest logs preserved at ${PRESERVED_LOGS}"
    fi
    exit "$exit_code"
}
trap cleanup EXIT INT TERM

cat > "${WORKDIR}/lima.yaml" <<EOF
# Generated by tests/podman-vm.sh -- generic Podman VM guest boot test.
# "plain" mode keeps the base guest setup (Cloud-init user + injected SSH
# key + host UID) intact, but disables mounts/port-forwarding/containerd/
# the Lima guest agent -- this is a generic FSDK image, not Lima's own
# Ubuntu-based default guest (docs/skills/vm-podman-guest.md).
plain: true
vmType: "qemu"
images:
- location: "${RAW}"
  arch: "${HOST_ARCH}"
cpus: 2
memory: "2GiB"
EOF

# 5. Boot and wait for SSH -------------------------------------------------
log "starting instance '${INSTANCE}' from $(basename "$RAW") (timeout ${BOOT_TIMEOUT}s)"
if ! LIMA_HOME="$WORKDIR" limactl start --tty=false --timeout "${BOOT_TIMEOUT}s" \
        --name "$INSTANCE" "${WORKDIR}/lima.yaml"; then
    fail "instance failed to boot/provision within ${BOOT_TIMEOUT}s -- see preserved logs"
fi
log "OK: instance running, SSH reachable"

# 6. Verify Cloud-init user provisioning -----------------------------------
HOST_UID="$(id -u)"
HOST_USER="$(id -un)"
GUEST_ID="$(LIMA_HOME="$WORKDIR" limactl shell "$INSTANCE" -- id)" \
    || fail "could not run 'id' inside the guest -- provisioning likely failed"
log "guest id: ${GUEST_ID}"
if ! echo "$GUEST_ID" | grep -q "uid=${HOST_UID}(${HOST_USER})"; then
    fail "guest user does not match host UID/name (expected uid=${HOST_UID}(${HOST_USER}), got: ${GUEST_ID})"
fi
log "OK: Cloud-init created the Lima user with the host UID (${HOST_UID})"

# shellcheck disable=SC2016 # $HOME must expand inside the guest shell, not the host
if ! LIMA_HOME="$WORKDIR" limactl shell "$INSTANCE" -- bash -c 'test -s "$HOME/.ssh/authorized_keys"'; then
    fail "guest \$HOME/.ssh/authorized_keys is missing or empty -- SSH key was not injected"
fi
log "OK: injected SSH key present in the guest's authorized_keys"

# 7. Rootless Podman smoke test ---------------------------------------------
log "running rootless 'podman run ${SMOKE_IMAGE}' smoke test in the guest"
SMOKE_OUT="$(LIMA_HOME="$WORKDIR" limactl shell "$INSTANCE" -- podman run --rm "$SMOKE_IMAGE" echo podman-vm-smoke-ok)" \
    || fail "rootless podman run failed inside the guest -- see preserved logs"
if ! echo "$SMOKE_OUT" | grep -q "podman-vm-smoke-ok"; then
    fail "podman run did not produce the expected smoke output (got: ${SMOKE_OUT})"
fi
log "OK: rootless podman run succeeded"

log "PASS: ${INSTANCE} booted, Cloud-init provisioned the Lima user correctly, podman smoke test passed"
