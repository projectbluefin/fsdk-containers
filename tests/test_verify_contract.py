"""Verification gates are derived from the record, not hand-written."""

from pathlib import Path
import sys
import unittest

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

    def test_every_published_image_has_a_ceiling(self):
        for record in catalog.load_all():
            with self.subTest(image=record["name"]):
                self.assertGreater(vc.gates_for(record)["max_bytes"], 0)

    def test_smoke_command_uses_the_entrypoint_by_default(self):
        record = catalog.load_record(ROOT / "catalog" / "python.yaml")
        self.assertEqual(vc.smoke_argv(record), ["--version"])

    def test_smoke_command_honours_an_override(self):
        record = catalog.load_record(ROOT / "catalog" / "skopeo.yaml")
        self.assertEqual(
            vc.smoke_argv(record), ["--entrypoint", "/usr/bin/skopeo", "--version"]
        )


if __name__ == "__main__":
    unittest.main()
