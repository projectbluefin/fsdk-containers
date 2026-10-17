"""Brew producer contracts: real Git identity, offline Ruby, immutable seed."""

import importlib.util
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).parents[1]
PREPARE = ROOT / "elements/brew/files/prepare-seed.sh"


class SeedTest(unittest.TestCase):
    def test_preserves_real_upstream_commit_tag_and_origin(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            repo, ruby, dest = root / "repo", root / "ruby", root / "dest"
            repo.mkdir()
            vendor = repo / "Library/Homebrew/vendor"
            vendor.mkdir(parents=True)
            (vendor / "portable-ruby-version").write_text("4.0.7\n")
            (repo / "bin").mkdir()
            (repo / "bin/brew").write_text("#!/bin/bash\nexit 0\n")
            (repo / "bin/brew").chmod(0o755)
            subprocess.run(["git", "init", "-b", "main", str(repo)], check=True, capture_output=True)
            subprocess.run(["git", "-C", str(repo), "add", "."], check=True)
            subprocess.run(["git", "-C", str(repo), "-c", "core.hooksPath=/dev/null",
                            "-c", "commit.gpgsign=false", "-c", "user.name=Upstream", "-c",
                            "user.email=upstream@example.test", "commit", "-m", "upstream"],
                           check=True, capture_output=True)
            commit = subprocess.check_output(["git", "-C", str(repo), "rev-parse", "HEAD"], text=True).strip()
            subprocess.run(["git", "-C", str(repo), "tag", "7.0.8"], check=True)
            # Mimic git_repo's detached, origin-less checkout, not a source archive.
            subprocess.run(["git", "-C", str(repo), "checkout", "--detach"], check=True, capture_output=True)
            # Match git_repo's tree-only export: worktree bytes remain, blob objects do not.
            blobs = subprocess.check_output(["git", "-C", str(repo), "ls-tree", "-r",
                                             "--format=%(objectname)", "HEAD"], text=True).splitlines()
            for blob in blobs:
                (repo / ".git/objects" / blob[:2] / blob[2:]).unlink()
            portable = ruby / "portable-ruby/4.0.7/bin"
            portable.mkdir(parents=True)
            (portable / "ruby").write_text("#!/bin/sh\nexit 0\n")
            (portable / "ruby").chmod(0o755)
            subprocess.run(["bash", str(PREPARE), str(repo), str(ruby), str(dest)], check=True)
            seed = dest / "usr/share/bluefin/homebrew-seed"
            brew = seed / "Homebrew"
            git = lambda *args: subprocess.check_output(["git", "-C", str(brew), *args], text=True).strip()
            self.assertEqual(git("rev-parse", "HEAD"), commit)
            self.assertEqual(git("rev-parse", "7.0.8"), commit)
            subprocess.run(["git", "-C", str(brew), "fsck", "--connectivity-only", "--no-dangling"],
                           check=True, capture_output=True)
            self.assertEqual(git("symbolic-ref", "HEAD"), "refs/heads/main")
            self.assertEqual(git("remote", "get-url", "origin"), "https://github.com/Homebrew/brew.git")
            self.assertEqual(git("config", "remote.origin.fetch"), "+refs/heads/*:refs/remotes/origin/*")
            self.assertEqual(git("config", "branch.main.remote"), "origin")
            self.assertEqual(git("config", "branch.main.merge"), "refs/heads/main")
            self.assertEqual(os.readlink(seed / "bin/brew"), "../Homebrew/bin/brew")
            self.assertEqual(os.readlink(brew / "Library/Homebrew/vendor/portable-ruby/current"), "4.0.7")
            self.assertTrue((seed / "Cellar").is_dir())
            self.assertEqual(list((seed / "Cellar").iterdir()), [])
            self.assertTrue((dest / "home/linuxbrew/.linuxbrew").is_dir())
            self.assertEqual(list((dest / "home/linuxbrew/.linuxbrew").iterdir()), [])
            second = root / "second"
            subprocess.run(["bash", str(PREPARE), str(repo), str(ruby), str(second)], check=True)
            second_git = second / "usr/share/bluefin/homebrew-seed/Homebrew/.git"
            self.assertEqual((brew / ".git/index").read_bytes(), (second_git / "index").read_bytes())
            self.assertFalse((brew / ".git/logs").exists(), "build-time reflog timestamps are not reproducible")

    def test_missing_git_metadata_is_rejected_not_reinitialized(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / "repo").mkdir()
            result = subprocess.run(["bash", str(PREPARE), str(root / "repo"), str(root / "ruby"),
                                     str(root / "dest")], capture_output=True, text=True)
            self.assertNotEqual(result.returncode, 0)
            self.assertIn("Git", result.stderr)




class RootfsVerifierTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        spec = importlib.util.spec_from_file_location("verify_brew", ROOT / "scripts/verify_brew.py")
        cls.verifier = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(cls.verifier)

    @staticmethod
    def elf_with_notes(target, entries):
        # Assemble real FDO notes and feed the resulting ELF through readelf.
        target.parent.mkdir(parents=True, exist_ok=True)
        payload = json.dumps(entries, separators=(",", ":"))
        assembly = (
            '.section .note.dlopen,"a",%note\n.balign 4\n'
            f'.long 4\n.long {len(payload.encode()) + 1}\n.long 0x407c0c0a\n'
            f'.asciz "FDO"\n.balign 4\n.asciz {json.dumps(payload)}\n.balign 4\n'
            '.section .note.GNU-stack,"",%progbits\n'
        )
        subprocess.run(["cc", "-shared", "-nostdlib", "-x", "assembler", "-", "-o", str(target)],
                       input=assembly, text=True, check=True, capture_output=True)

    def test_missing_required_dlopen_dependency_is_rejected(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            program = root / "usr/lib/systemd/boot-helper"
            self.elf_with_notes(program, [{"soname": ["librequired.so.0"], "priority": "required"}])
            with self.assertRaisesRegex(ValueError, "missing required dlopen library librequired.so.0"):
                self.verifier.verify_elf(root, [program])

    def test_optional_dlopen_dependencies_do_not_become_mandatory(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            program = root / "usr/bin/helper"
            self.elf_with_notes(program, [
                {"soname": ["librecommended.so.0"], "priority": "recommended"},
                {"soname": ["libsuggested.so.0"], "priority": "suggested"},
                {"soname": ["libdefault.so.0"]},
                {"soname": ["libmandatory.so.0"], "priority": "required"},
            ])
            with self.assertRaisesRegex(ValueError, "missing required dlopen library libmandatory.so.0"):
                self.verifier.verify_elf(root, [program])

    def test_required_soname_alternative_checks_selected_library_closure(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            program = root / "usr/bin/helper"
            self.elf_with_notes(program, [{"soname": ["libfeature.so.2", "libfeature.so.1"],
                                           "priority": "required"}])
            self.elf_with_notes(root / "usr/lib/libfeature.so.1", [
                {"soname": ["libnested.so.0"], "priority": "required"},
            ])
            with self.assertRaisesRegex(ValueError, "missing required dlopen library libnested.so.0"):
                self.verifier.verify_elf(root, [program])


    def test_empty_rootfs_is_rejected(self):
        with tempfile.TemporaryDirectory() as directory:
            with self.assertRaisesRegex(ValueError, "missing"):
                self.verifier.verify_root(Path(directory), "7.0.8", "a57af195cf9d7addb48bdb1204c9151313cd0057")

    def test_corrupt_and_missing_checksums_fail_closed(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / "homebrew-env-7.0.8.tar.zst").write_bytes(b"changed")
            (root / "homebrew-env-7.0.8.raw.zst").write_bytes(b"raw")
            (root / "SHA256SUMS").write_text("0" * 64 + " *homebrew-env-7.0.8.tar.zst\n")
            with self.assertRaises(ValueError):
                self.verifier.verify_checksums(root, "7.0.8")

    def test_absolute_symlinks_resolve_within_guest_not_host(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / "etc/pam.d").mkdir(parents=True)
            (root / "usr/lib/pam.d").mkdir(parents=True)
            vendor = root / "usr/lib/pam.d/systemd-user"
            vendor.write_text("auth required pam_rootok.so\nsession optional pam_systemd.so\n")
            (root / "etc/pam.d/systemd-user").symlink_to("/usr/lib/pam.d/systemd-user")
            self.assertEqual(self.verifier.in_root(root, "etc/pam.d/systemd-user"), vendor)

    def test_checksum_contract_accepts_exactly_both_correct_artifacts(self):
        import hashlib
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            checksums = []
            for format in ("tar", "raw"):
                name = f"homebrew-env-7.0.8.{format}.zst"
                content = format.encode()
                (root / name).write_bytes(content)
                checksums.append(f"{hashlib.sha256(content).hexdigest()} *{name}\n")
            (root / "SHA256SUMS").write_text("".join(checksums))
            self.verifier.verify_checksums(root, "7.0.8")
            (root / "homebrew-env-7.0.8.raw.zst").write_bytes(b"corrupt")
            with self.assertRaisesRegex(ValueError, "checksum mismatch"):
                self.verifier.verify_checksums(root, "7.0.8")


if __name__ == "__main__":
    unittest.main()
