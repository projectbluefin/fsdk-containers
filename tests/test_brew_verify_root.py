"""Host-only tests for scripts/verify_brew.py verify_root and in_root.

The verify-brew CI job only ever feeds verify_root a freshly built, valid
machine, so none of its refusals run there. These tests build a minimal valid
guest root (plain files, a real Git seed) and break one property at a time.
"""
import importlib.util
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
VERSION = "4.6.0"
RUBY = "3.4.1"


def load_verifier():
    spec = importlib.util.spec_from_file_location("verify_brew", ROOT / "scripts/verify_brew.py")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def git(directory, *args):
    env = {
        "PATH": os.environ["PATH"], "HOME": str(directory),
        "GIT_CONFIG_NOSYSTEM": "1", "GIT_CONFIG_GLOBAL": os.devnull,
        "GIT_AUTHOR_NAME": "t", "GIT_AUTHOR_EMAIL": "t@example.invalid",
        "GIT_COMMITTER_NAME": "t", "GIT_COMMITTER_EMAIL": "t@example.invalid",
    }
    return subprocess.run(["git", "-C", str(directory), *args], env=env, check=True,
                          capture_output=True, text=True).stdout.strip()


class VerifyRootTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.verifier = load_verifier()

    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name) / "root"

    def write(self, relative, content="", mode=None):
        path = self.root / relative
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(content)
        if mode is not None:
            path.chmod(mode)
        return path

    def symlink(self, relative, target):
        path = self.root / relative
        path.parent.mkdir(parents=True, exist_ok=True)
        if path.is_symlink() or path.exists():
            path.unlink()
        path.symlink_to(target)

    def build(self, raw=True):
        """Return (root, commit) for a guest root that verify_root accepts."""
        for name in self.verifier.REQUIRED:
            self.write(name, "placeholder\n")
        self.write("etc/machine-id", "")
        self.write("etc/locale.conf", "LANG=C.UTF-8\n")
        self.write("etc/passwd", "root:x:0:0::/root:/bin/bash\nlinuxbrew:x:1001:1001::/home/linuxbrew:/bin/bash\n")
        self.write("etc/nsswitch.conf", "passwd: files systemd\n")
        self.write("etc/pam.d/systemd-user", "session optional pam_systemd.so\n")
        self.symlink("sbin/init", "/usr/lib/systemd/systemd")
        self.write("usr/lib/x86_64-linux-gnu/libnss_systemd.so.2", "not elf\n")
        self.write("usr/lib/x86_64-linux-gnu/security/pam_systemd.so", "not elf\n")

        self.seed = self.root / ("usr/share/bluefin/homebrew-seed" if raw else "home/linuxbrew/.linuxbrew")
        (self.root / "home/linuxbrew/.linuxbrew").mkdir(parents=True, exist_ok=True)
        self.brew = self.seed / "Homebrew"
        vendor = "Library/Homebrew/vendor"
        self.write(self.brew.relative_to(self.root) / f"{vendor}/portable-ruby-version", RUBY + "\n")
        self.write(self.brew.relative_to(self.root) / f"{vendor}/portable-ruby/{RUBY}/bin/ruby", "ruby\n", 0o755)
        self.symlink(self.brew.relative_to(self.root) / f"{vendor}/portable-ruby/current", RUBY)
        self.write(self.brew.relative_to(self.root) / "bin/brew", "#!/bin/sh\n", 0o755)
        self.symlink(self.seed.relative_to(self.root) / "bin/brew", "../Homebrew/bin/brew")
        (self.seed / "Cellar").mkdir(parents=True, exist_ok=True)

        git(self.brew, "init", "-q", "-b", "main")
        git(self.brew, "add", "-A")
        git(self.brew, "commit", "-q", "-m", "release")
        git(self.brew, "tag", VERSION)
        git(self.brew, "remote", "add", "origin", "https://github.com/Homebrew/brew.git")
        return self.root, git(self.brew, "rev-parse", "HEAD")

    def assert_rejected(self, pattern, raw=True, commit=None):
        with self.assertRaisesRegex(ValueError, pattern):
            self.verifier.verify_root(self.root, VERSION, commit or self.commit, raw=raw)

    def test_valid_raw_and_tar_roots_are_accepted(self):
        for raw in (True, False):
            with self.subTest(raw=raw), tempfile.TemporaryDirectory() as directory:
                self.root = Path(directory) / "root"
                _, commit = self.build(raw=raw)
                self.verifier.verify_root(self.root, VERSION, commit, raw=raw)

    def test_each_missing_prerequisite_is_named(self):
        _, self.commit = self.build()
        for name in ("usr/bin/git", "etc/subgid", "usr/lib/systemd/user/dbus.socket"):
            with self.subTest(name=name):
                path = self.root / name
                content = path.read_text()
                path.unlink()
                self.assert_rejected("missing guest prerequisite: " + name)
                path.write_text(content)

    def test_guest_identity_refusals(self):
        cases = [
            ("init must resolve to guest systemd", lambda: self.symlink("sbin/init", "/usr/bin/bash")),
            ("machine-id must be empty", lambda: self.write("etc/machine-id", "0123456789abcdef\n")),
            ("missing UTF-8 locale", lambda: self.write("etc/locale.conf", "LANG=en_US.UTF-8\n")),
            ("missing nonroot linuxbrew user", lambda: self.write("etc/passwd", "linuxbrew:x:0:0::/:/bin/sh\n")),
            ("guest NSS must resolve systemd users", lambda: self.write("etc/nsswitch.conf", "passwd: files\n")),
            ("guest PAM must initialize user sessions", lambda: self.write("etc/pam.d/systemd-user", "session required pam_unix.so\n")),
        ]
        for message, breaker in cases:
            with self.subTest(message=message), tempfile.TemporaryDirectory() as directory:
                self.root = Path(directory) / "root"
                _, self.commit = self.build()
                breaker()
                self.assert_rejected(message)

    def test_pam_config_is_read_through_guest_symlink(self):
        _, self.commit = self.build()
        self.write("usr/lib/pam.d/systemd-user", "session optional pam_systemd.so\n")
        self.symlink("etc/pam.d/systemd-user", "/usr/lib/pam.d/systemd-user")
        self.verifier.verify_root(self.root, VERSION, self.commit)
        (self.root / "usr/lib/pam.d/systemd-user").write_text("session required pam_unix.so\n")
        self.assert_rejected("guest PAM must initialize user sessions")

    def test_seed_git_identity_refusals(self):
        cases = [
            ("missing real upstream Git repository", lambda: subprocess.run(["rm", "-rf", str(self.brew / ".git")], check=True)),
            ("not the pinned upstream release", lambda: git(self.brew, "commit", "-q", "--allow-empty", "-m", "drift")),
            ("not the pinned upstream release", lambda: self.retag()),
            ("seed origin does not permit upstream brew update",
             lambda: git(self.brew, "remote", "set-url", "origin", "https://example.invalid/brew.git")),
            ("seed lacks upstream fetch refspec",
             lambda: git(self.brew, "config", "remote.origin.fetch", "+refs/heads/main:refs/remotes/origin/main")),
            ("seed must have an updatable upstream branch", lambda: git(self.brew, "branch", "-q", "-m", "main", "stable")),
        ]
        for message, breaker in cases:
            with self.subTest(message=message), tempfile.TemporaryDirectory() as directory:
                self.root = Path(directory) / "root"
                _, self.commit = self.build()
                breaker()
                self.assert_rejected(message)

    def retag(self):
        # Tag names a different commit than HEAD, while HEAD stays pinned.
        git(self.brew, "checkout", "-q", "-b", "side")
        git(self.brew, "commit", "-q", "--allow-empty", "-m", "side")
        git(self.brew, "tag", "-f", VERSION)
        git(self.brew, "checkout", "-q", "main")

    def test_wrong_commit_argument_is_rejected(self):
        self.build()
        self.assert_rejected("not the pinned upstream release", commit="0" * 40)

    def test_disconnected_seed_history_fails_fsck(self):
        _, self.commit = self.build()
        objects = self.brew / ".git/objects"
        tree = git(self.brew, "rev-parse", "HEAD^{tree}")
        (objects / tree[:2] / tree[2:]).unlink()
        with self.assertRaises(subprocess.CalledProcessError):
            self.verifier.verify_root(self.root, VERSION, self.commit)

    def test_seed_layout_refusals(self):
        vendor = "Library/Homebrew/vendor"
        cases = [
            ("portable Ruby current does not match pinned brew",
             lambda: self.symlink((self.brew / f"{vendor}/portable-ruby/current").relative_to(self.root), "3.3.0")),
            ("missing runnable matching portable Ruby",
             lambda: (self.brew / f"{vendor}/portable-ruby/{RUBY}/bin/ruby").chmod(0o644)),
            ("missing runnable matching portable Ruby",
             lambda: (self.brew / f"{vendor}/portable-ruby/{RUBY}/bin/ruby").unlink()),
            ("brew entrypoint is not canonical",
             lambda: self.symlink((self.seed / "bin/brew").relative_to(self.root), "/usr/bin/brew")),
            ("producer must not install formulae", lambda: (self.seed / "Cellar/jq").mkdir()),
            ("raw prefix mountpoint must not duplicate seed",
             lambda: (self.root / "home/linuxbrew/.linuxbrew/bin").mkdir()),
            ("missing NSS/PAM modules", lambda: (self.root / "usr/lib/x86_64-linux-gnu/libnss_systemd.so.2").unlink()),
            ("missing NSS/PAM modules",
             lambda: (self.root / "usr/lib/x86_64-linux-gnu/security/pam_systemd.so").unlink()),
        ]
        for message, breaker in cases:
            with self.subTest(message=message), tempfile.TemporaryDirectory() as directory:
                self.root = Path(directory) / "root"
                _, self.commit = self.build()
                breaker()
                self.assert_rejected(message)

    def test_tar_layout_is_not_accepted_as_raw(self):
        # The tar seed lives in home/linuxbrew/.linuxbrew; raw expects it under usr/share.
        _, self.commit = self.build(raw=False)
        self.verifier.verify_root(self.root, VERSION, self.commit, raw=False)
        self.assert_rejected("missing real upstream Git repository", raw=True)


class InRootTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.verifier = load_verifier()

    def test_dotdot_cannot_escape_guest_root(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            with self.assertRaisesRegex(ValueError, "guest symlink escapes root"):
                self.verifier.in_root(root, "../etc/passwd")
            (root / "usr").mkdir()
            (root / "usr/escape").symlink_to("../../outside")
            with self.assertRaisesRegex(ValueError, "guest symlink escapes root"):
                self.verifier.in_root(root, "usr/escape")

    def test_dotdot_within_root_resolves(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / "usr/lib").mkdir(parents=True)
            (root / "usr/lib/up").symlink_to("../bin/./tool")
            self.assertEqual(self.verifier.in_root(root, "/usr/lib/up"), root / "usr/bin/tool")

    def test_symlink_loop_is_rejected(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / "a").symlink_to("b")
            (root / "b").symlink_to("/a")
            with self.assertRaisesRegex(ValueError, "guest symlink loop"):
                self.verifier.in_root(root, "a")

    def test_chain_of_forty_links_still_resolves(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / "target").write_text("")
            for index in range(40):
                (root / f"l{index}").symlink_to("target" if index == 39 else f"l{index + 1}")
            self.assertEqual(self.verifier.in_root(root, "l0"), root / "target")
            (root / "l39").unlink()
            (root / "l39").symlink_to("l40")
            (root / "l40").symlink_to("target")
            with self.assertRaisesRegex(ValueError, "guest symlink loop"):
                self.verifier.in_root(root, "l0")


if __name__ == "__main__":
    unittest.main()
