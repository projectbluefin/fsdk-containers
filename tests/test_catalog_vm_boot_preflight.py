"""`tests/vm-boot.sh` decides whether a VM disk is safe to boot, untested.

The script is the gate `.github/actions/vm-boot-test` runs, and it is 300+
lines of bash whose first third never reaches QEMU: it resolves the artifact,
derives the architecture from the artifact's *name*, and refuses to boot a disk
whose `sha256sum --binary` manifest does not verify. Every one of those
decisions is a refusal -- the script's own header promises "nothing here is a
skip" -- and none of them were exercised by anything. They ran only inside the
full boot job, which needs a built disk, QEMU, UEFI firmware and, under TCG,
half an hour; so on a pull request that touches the harness, the refusal paths
were argued about rather than run.

A fail-open bug here is silent by construction. If the manifest-coverage grep
stops matching, a stale `.sha256` left beside a different disk "verifies" a
disk that was never hashed. If the architecture case stops matching, an
aarch64 disk is handed to `qemu-system-x86_64` and the boot failure is blamed
on the image. Neither shows up as a red build; both show up as a green one.

These tests execute the real script. Each case stages a throwaway repository
root holding a byte-identical copy of `tests/vm-boot.sh`, runs it under a
PATH built from scratch, and asserts on its exit status and message. The PATH
is the instrument: when it carries stub `qemu-img`/`qemu-system-*` that record
their own invocation, a test can prove the script *never reached QEMU*, which
is the actual safety claim. When it carries no QEMU at all, the script's
tooling preflight is reached, which proves the preceding checks passed rather
than silently skipped.

Nothing here boots anything, and no test takes longer than a subprocess.
"""

from pathlib import Path
import hashlib
import os
import shutil
import subprocess
import tempfile
import unittest


ROOT = Path(__file__).parents[1]
VM_BOOT = ROOT / "tests" / "vm-boot.sh"

# Everything the script shells out to before it would launch QEMU. `command -v`
# and `printf` are bash builtins and need no entry.
REQUIRED_TOOLS = (
    "basename",
    "cat",
    "cp",
    "cut",
    "date",
    "dirname",
    "find",
    "grep",
    "mkdir",
    "mktemp",
    "rm",
    "sed",
    "sha256sum",
    "sleep",
    "tr",
    "uname",
)

QEMU_STUB = """#!/bin/sh
printf '%s %s\\n' "$(basename "$0")" "$*" >>"{record}"
exit 0
"""


class VmBootPreflightTests(unittest.TestCase):
    """Black-box coverage for the refusals `tests/vm-boot.sh` makes."""

    def setUp(self):
        self.tmp = Path(tempfile.mkdtemp(prefix="vm-boot-preflight."))
        self.addCleanup(shutil.rmtree, self.tmp, ignore_errors=True)

        # A throwaway repository root, so `dist-vm/` and `tests/artifacts/`
        # belong to the test rather than to the checkout.
        self.repo = self.tmp / "repo"
        (self.repo / "tests").mkdir(parents=True)
        self.script = self.repo / "tests" / "vm-boot.sh"
        shutil.copy2(VM_BOOT, self.script)
        self.assertEqual(
            self.script.read_bytes(),
            VM_BOOT.read_bytes(),
            "the staged copy must be the shipped script, not a paraphrase",
        )

        self.bin = self.tmp / "bin"
        self.bin.mkdir()
        for tool in REQUIRED_TOOLS:
            found = shutil.which(tool)
            if found is None:  # pragma: no cover - a host without coreutils
                self.skipTest(f"{tool} is not available on this host")
            os.symlink(found, self.bin / tool)

        self.qemu_record = self.tmp / "qemu-invocations"

        self.bash = shutil.which("bash")
        if self.bash is None:  # pragma: no cover - a host without bash
            self.skipTest("bash is not available on this host")

    # -- helpers ----------------------------------------------------------

    def install_qemu_stubs(self):
        """Put recording `qemu-img`/`qemu-system-*` stubs on the PATH.

        Their only job is to make "QEMU was reached" observable, so a test can
        assert the opposite.
        """
        for name in ("qemu-img", "qemu-system-x86_64", "qemu-system-aarch64"):
            stub = self.bin / name
            stub.write_text(QEMU_STUB.format(record=self.qemu_record))
            stub.chmod(0o755)

    def qemu_was_invoked(self):
        return self.qemu_record.exists()

    def write_disk(self, name, content=b"not really a disk", manifest=True,
                   manifest_name=None, manifest_digest=None, binary_mode=True,
                   directory=None):
        """Write a fake raw disk and, by default, a manifest that covers it."""
        directory = directory or (self.repo / "dist-vm")
        directory.mkdir(parents=True, exist_ok=True)
        disk = directory / name
        disk.write_bytes(content)
        if manifest:
            digest = manifest_digest or hashlib.sha256(content).hexdigest()
            covered = manifest_name or name
            separator = " *" if binary_mode else "  "
            (directory / f"{name}.sha256").write_text(
                f"{digest}{separator}{covered}\n"
            )
        return disk

    def run_script(self, *args, env=None, timeout=60):
        environment = {
            "PATH": str(self.bin),
            "HOME": str(self.tmp),
            "SHELL": "/bin/bash",
        }
        environment.update(env or {})
        return subprocess.run(
            [self.bash, str(self.script), *args],
            capture_output=True,
            text=True,
            env=environment,
            cwd=self.tmp,
            timeout=timeout,
        )

    def assertRefused(self, result, needle):
        """A refusal is a non-zero exit carrying an actionable message."""
        self.assertNotEqual(
            result.returncode,
            0,
            f"expected a hard failure, got a pass. stderr:\n{result.stderr}",
        )
        self.assertIn(needle, result.stderr)

    # -- 1. resolving the artifact ----------------------------------------

    def test_no_artifact_anywhere_is_a_failure_not_a_skip(self):
        (self.repo / "dist-vm").mkdir()
        result = self.run_script()
        self.assertRefused(result, "no raw disk supplied")
        self.assertIn("just export-podman-vm", result.stderr)

    def test_an_ambiguous_dist_vm_is_refused_rather_than_guessed(self):
        self.write_disk("donate-clanker-vm-1.0-x86_64.raw")
        self.write_disk("donate-clanker-vm-2.0-x86_64.raw")
        result = self.run_script()
        self.assertRefused(result, "does not contain exactly one (found 2)")

    def test_a_single_dist_vm_disk_is_adopted_without_an_argument(self):
        self.write_disk("donate-clanker-vm-1.0-x86_64.raw", manifest=False)
        result = self.run_script()
        # Resolution succeeded: the script got far enough to want a manifest
        # for that exact disk.
        self.assertRefused(result, "checksum manifest not found")
        self.assertIn("donate-clanker-vm-1.0-x86_64.raw.sha256", result.stderr)

    def test_podman_vm_raw_is_honoured_when_no_argument_is_given(self):
        disk = self.write_disk(
            "donate-clanker-vm-1.0-x86_64.raw",
            manifest=False,
            directory=self.tmp / "elsewhere",
        )
        result = self.run_script(env={"PODMAN_VM_RAW": str(disk)})
        self.assertRefused(result, "checksum manifest not found")
        self.assertIn(str(disk), result.stderr)

    def test_a_missing_artifact_is_never_treated_as_a_pass(self):
        result = self.run_script(str(self.tmp / "absent.raw"))
        self.assertRefused(result, "artifact not found")

    # -- 2. architecture comes from the name ------------------------------

    def test_an_underivable_architecture_is_refused(self):
        disk = self.write_disk("donate-clanker-vm-1.0.raw")
        result = self.run_script(str(disk))
        self.assertRefused(result, "cannot derive the architecture")

    def test_the_architecture_is_read_from_the_name_not_the_host(self):
        """An aarch64 disk must never be handed to qemu-system-x86_64."""
        disk = self.write_disk("donate-clanker-vm-1.0-aarch64.raw")
        result = self.run_script(str(disk))
        # No QEMU on the PATH, so the tooling preflight reports which binary
        # the script had decided to use -- the assertion this test exists for.
        self.assertRefused(result, "qemu-system-aarch64 not found in PATH")
        self.assertNotIn("qemu-system-x86_64", result.stderr)

    def test_an_x86_64_disk_selects_the_x86_64_emulator(self):
        disk = self.write_disk("donate-clanker-vm-1.0-x86_64.raw")
        result = self.run_script(str(disk))
        self.assertRefused(result, "qemu-system-x86_64 not found in PATH")

    # -- 3. the manifest must cover *this* disk ---------------------------

    def test_a_missing_manifest_is_a_hard_failure(self):
        disk = self.write_disk("donate-clanker-vm-1.0-x86_64.raw", manifest=False)
        self.install_qemu_stubs()
        result = self.run_script(str(disk))
        self.assertRefused(result, "checksum manifest not found")
        self.assertFalse(
            self.qemu_was_invoked(),
            "an unverifiable disk must not reach QEMU",
        )

    def test_a_manifest_for_a_different_disk_does_not_verify_this_one(self):
        """The guard against a stale `.sha256` in the same directory.

        `sha256sum -c` checks the name written *in* the manifest. A manifest
        naming another disk would otherwise pass while the disk under test was
        never hashed at all.
        """
        self.write_disk("donate-clanker-vm-0.9-x86_64.raw")
        disk = self.write_disk(
            "donate-clanker-vm-1.0-x86_64.raw",
            manifest_name="donate-clanker-vm-0.9-x86_64.raw",
            manifest_digest=hashlib.sha256(b"not really a disk").hexdigest(),
        )
        self.install_qemu_stubs()
        result = self.run_script(str(disk))
        self.assertRefused(result, "does not cover")
        self.assertFalse(
            self.qemu_was_invoked(),
            "a disk covered by nobody's manifest must not reach QEMU",
        )

    def test_a_corrupt_disk_is_refused_before_anything_boots(self):
        disk = self.write_disk(
            "donate-clanker-vm-1.0-x86_64.raw",
            manifest_digest="0" * 64,
        )
        self.install_qemu_stubs()
        result = self.run_script(str(disk))
        self.assertRefused(result, "refusing to boot it")
        self.assertFalse(
            self.qemu_was_invoked(),
            "a corrupt disk must not reach QEMU",
        )

    def test_a_binary_mode_manifest_verifies(self):
        """`sha256sum --binary` writes `<digest> *<name>`; that must pass."""
        disk = self.write_disk(
            "donate-clanker-vm-1.0-x86_64.raw", binary_mode=True
        )
        result = self.run_script(str(disk))
        self.assertIn("OK: checksum verified", result.stderr)
        self.assertRefused(result, "qemu-system-x86_64 not found in PATH")

    def test_a_text_mode_manifest_verifies(self):
        disk = self.write_disk(
            "donate-clanker-vm-1.0-x86_64.raw", binary_mode=False
        )
        result = self.run_script(str(disk))
        self.assertIn("OK: checksum verified", result.stderr)
        self.assertRefused(result, "qemu-system-x86_64 not found in PATH")

    # -- 4. the documented escape hatch stays narrow ----------------------

    def test_skipping_the_checksum_warns_and_still_refuses_to_pass(self):
        """`PODMAN_VM_SKIP_CHECKSUM=1` skips verification, not the test."""
        disk = self.write_disk(
            "donate-clanker-vm-1.0-x86_64.raw",
            manifest=False,
        )
        result = self.run_script(
            str(disk), env={"PODMAN_VM_SKIP_CHECKSUM": "1"}
        )
        self.assertIn("checksum verification disabled", result.stderr)
        self.assertRefused(result, "qemu-system-x86_64 not found in PATH")

    def test_skipping_the_checksum_requires_the_exact_value_one(self):
        """Any other value keeps verification on, so a typo cannot disable it."""
        disk = self.write_disk(
            "donate-clanker-vm-1.0-x86_64.raw",
            manifest=False,
        )
        for value in ("0", "true", "yes", ""):
            with self.subTest(value=value):
                result = self.run_script(
                    str(disk), env={"PODMAN_VM_SKIP_CHECKSUM": value}
                )
                self.assertRefused(result, "checksum manifest not found")

    # -- 5. the preflight leaves nothing behind ---------------------------

    def test_a_preflight_refusal_creates_no_artifacts_directory(self):
        """Failing before QEMU must not fabricate an empty evidence dir."""
        disk = self.write_disk(
            "donate-clanker-vm-1.0-x86_64.raw", manifest_digest="0" * 64
        )
        self.install_qemu_stubs()
        self.run_script(str(disk))
        self.assertFalse(
            (self.repo / "tests" / "artifacts").exists(),
            "tests/artifacts/ is the boot job's evidence, not a preflight's",
        )


if __name__ == "__main__":  # pragma: no cover
    unittest.main()
