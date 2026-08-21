"""Verification gates are derived from the record, not hand-written."""

import contextlib
import io
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest import mock

ROOT = Path(__file__).parents[1]
sys.path.insert(0, str(ROOT / "scripts"))

import catalog  # noqa: E402
import verify_contract as vc  # noqa: E402


class GateDerivationTests(unittest.TestCase):
    def test_distroless_images_forbid_a_shell(self):
        record = catalog.load_record(ROOT / "catalog" / "base.yaml")
        gates = vc.gates_for(record)
        self.assertIn("no-shell", gates["forbid"])

    def test_shell_enabled_images_require_a_shell(self):
        record = catalog.load_record(ROOT / "catalog" / "lab-runner.yaml")
        gates = vc.gates_for(record)
        self.assertNotIn("no-shell", gates["forbid"])
        self.assertIn("bash", gates["require_binaries"])

    def test_size_ceiling_comes_from_the_record(self):
        record = catalog.load_record(ROOT / "catalog" / "python.yaml")
        self.assertEqual(vc.gates_for(record)["max_bytes"], 144 * 1024 * 1024)

    def test_tzdata_and_ca_are_gated_on_every_distroless_image(self):
        """Regression: static declares no require_paths, and deriving the
        baseline from the record silently dropped its tzdata check."""
        for record in catalog.load_all():
            if record["kind"] != "distroless":
                continue
            with self.subTest(image=record["name"]):
                paths = vc.require_paths_for(record)
                self.assertIn("usr/share/zoneinfo/UTC", paths)
                # CA check uses any-of alternatives, not a single fixed path
                any_paths = vc.require_any_paths_for(record)
                self.assertIn("etc/pki/tls/certs/ca-bundle.crt", any_paths)
                self.assertIn("etc/ssl/certs/ca-certificates.crt", any_paths)

    def test_lab_runner_has_no_distroless_only_gates(self):
        """Finding 1: lab-runner must not have no-sanitizers or no-locale-archive.
        The old recipe ran neither in its lab-runner branch."""
        record = catalog.load_record(ROOT / "catalog" / "lab-runner.yaml")
        gates = vc.gates_for(record)
        self.assertNotIn("no-sanitizers", gates["forbid"])
        self.assertNotIn("no-locale-archive", gates["forbid"])

    def test_lab_runner_has_no_ca_any_paths(self):
        """Finding 2: the old recipe applied no CA gate to lab-runner."""
        record = catalog.load_record(ROOT / "catalog" / "lab-runner.yaml")
        self.assertEqual(vc.require_any_paths_for(record), [])

    def test_shell_enabled_images_keep_their_old_baseline(self):
        """The old recipe applied neither check to lab-runner; adding them
        would be a new gate, which this plan forbids."""
        record = catalog.load_record(ROOT / "catalog" / "lab-runner.yaml")
        paths = vc.require_paths_for(record)
        self.assertNotIn("usr/share/zoneinfo/UTC", paths)

    def test_every_published_image_has_a_ceiling(self):
        for record in catalog.load_all():
            with self.subTest(image=record["name"]):
                self.assertGreater(vc.gates_for(record)["max_bytes"], 0)

    def test_smoke_command_uses_the_entrypoint_by_default(self):
        record = catalog.load_record(ROOT / "catalog" / "python.yaml")
        self.assertEqual(vc.smoke_argv(record), ["--version"])

    def test_smoke_command_honours_an_override(self):
        """skopeo has no entrypoint; its smoke test must use the positional form."""
        record = catalog.load_record(ROOT / "catalog" / "skopeo.yaml")
        argv = vc.smoke_argv(record)
        # No --entrypoint override; skopeo is CMD, proving PATH resolution
        self.assertNotIn("--entrypoint", argv)
        self.assertEqual(argv, ["skopeo", "--version"])


class SmokeSplitTests(unittest.TestCase):
    """smoke_split separates podman options (before the image ref) from the
    CMD arguments (after it)."""

    def test_no_smoke_block_gives_empty_lists(self):
        for name in ("base", "static"):
            with self.subTest(image=name):
                record = catalog.load_record(ROOT / "catalog" / f"{name}.yaml")
                self.assertEqual(vc.smoke_split(record), ([], []))

    def test_todays_records_split_where_expected(self):
        expected = {
            # podman run --rm "$REF" --version
            "python": ([], ["--version"]),
            # podman run --rm "$REF" skopeo --version
            "skopeo": ([], ["skopeo", "--version"]),
            # podman run --rm --entrypoint /usr/bin/argo "$REF" version --short
            "lab-runner": (
                ["--entrypoint", "/usr/bin/argo"],
                ["version", "--short"],
            ),
        }
        for name, want in expected.items():
            with self.subTest(image=name):
                record = catalog.load_record(ROOT / "catalog" / f"{name}.yaml")
                self.assertEqual(vc.smoke_split(record), want)

    def test_split_preserves_the_full_argv(self):
        for record in catalog.load_all():
            with self.subTest(image=record["name"]):
                opts, cmd_args = vc.smoke_split(record)
                self.assertEqual(opts + cmd_args, vc.smoke_argv(record))


class SmokeArgBoundaryTests(unittest.TestCase):
    """Finding 4: smoke arguments must reach podman with their boundaries
    intact. SMOKE_OPTS/SMOKE_ARGS are emitted newline-delimited (one argument
    per line) and the Justfile reads them with mapfile into bash arrays, so a
    multi-word argument or a glob character survives as exactly one argument.
    """

    def _env_output(self, record: dict) -> str:
        """The --env text verify_contract emits for a synthetic record."""
        with mock.patch.object(vc.catalog, "load_record", return_value=record):
            argv = sys.argv
            sys.argv = ["verify_contract.py", "synthetic", "--env"]
            try:
                buf = io.StringIO()
                with contextlib.redirect_stdout(buf):
                    vc.main()
            finally:
                sys.argv = argv
        return buf.getvalue()

    def _bash_roundtrip(self, env_output: str, cwd: str) -> tuple[list[str], list[str]]:
        """Replay exactly what the Justfile does: eval the --env output, then
        mapfile the newline-delimited vars into arrays. Returns (opts, args)."""
        script = (
            'eval "$1"\n'
            "O=()\n"
            'if [ -n "$SMOKE_OPTS" ]; then mapfile -t O <<< "$SMOKE_OPTS"; fi\n'
            "A=()\n"
            'if [ -n "$SMOKE_ARGS" ]; then mapfile -t A <<< "$SMOKE_ARGS"; fi\n'
            'for x in "${O[@]}"; do printf "%s\\0" "$x"; done\n'
            'printf "%s\\0" "--REF--"\n'
            'for x in "${A[@]}"; do printf "%s\\0" "$x"; done\n'
        )
        out = subprocess.run(
            ["bash", "-c", script, "bash", env_output],
            check=True, capture_output=True, cwd=cwd,
        ).stdout
        fields = [f.decode() for f in out.split(b"\0")]
        if fields and fields[-1] == "":
            fields.pop()  # trailing NUL after the last field
        sep = fields.index("--REF--")
        return fields[:sep], fields[sep + 1:]

    @staticmethod
    def _record(args: list[str], override: list[str] | None = None) -> dict:
        record = {
            "name": "synthetic",
            "kind": "distroless",
            "description": "synthetic record for smoke boundary tests",
            "size_ceiling_mib": 64,
            "stack": {"depends": []},
            "smoke": {"args": args},
        }
        if override:
            record["smoke"]["entrypoint_override"] = override
        return record

    def test_argument_with_a_space_stays_one_argument(self):
        env = self._env_output(self._record(["echo", "hello world"]))
        opts, args = self._bash_roundtrip(env, cwd=str(ROOT))
        self.assertEqual(opts, [])
        self.assertEqual(args, ["echo", "hello world"])

    def test_glob_character_is_never_expanded(self):
        # Run the roundtrip in a directory where *.tar.gz WOULD match, so any
        # unquoted expansion (the old behaviour) is caught, not just missed.
        with tempfile.TemporaryDirectory(dir=ROOT) as d:
            Path(d, "a.tar.gz").touch()
            env = self._env_output(self._record(["--include", "*.tar.gz"]))
            opts, args = self._bash_roundtrip(env, cwd=d)
        self.assertEqual(opts, [])
        self.assertEqual(args, ["--include", "*.tar.gz"])

    def test_entrypoint_override_with_a_space_stays_one_option(self):
        env = self._env_output(
            self._record(["serve", "--title", "a b"], override=["/opt/my tool/run"])
        )
        opts, args = self._bash_roundtrip(env, cwd=str(ROOT))
        self.assertEqual(opts, ["--entrypoint", "/opt/my tool/run"])
        self.assertEqual(args, ["serve", "--title", "a b"])

    def test_no_smoke_block_yields_empty_arrays(self):
        record = self._record(["--version"])
        del record["smoke"]
        env = self._env_output(record)
        opts, args = self._bash_roundtrip(env, cwd=str(ROOT))
        self.assertEqual(opts, [])
        self.assertEqual(args, [])


if __name__ == "__main__":
    unittest.main()
