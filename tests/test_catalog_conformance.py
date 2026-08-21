"""Every published image has a record, and every record has an image."""

import json
from pathlib import Path
import sys
import unittest

ROOT = Path(__file__).parents[1]
sys.path.insert(0, str(ROOT / "scripts"))

import catalog  # noqa: E402

TARGETS = json.loads((ROOT / "elements" / "targets.json").read_text())


class CatalogCoverageTests(unittest.TestCase):
    def test_every_published_image_has_a_record(self):
        recorded = {r["name"] for r in catalog.load_all()}
        published = set(TARGETS["oci_images"])
        self.assertEqual(
            published - recorded,
            set(),
            "published images with no catalog record",
        )

    def test_every_record_is_a_published_image(self):
        recorded = {r["name"] for r in catalog.load_all()}
        published = set(TARGETS["oci_images"])
        self.assertEqual(
            recorded - published,
            set(),
            "catalog records for images not in targets.json oci_images",
        )

    def test_exactly_one_shell_enabled_image(self):
        shell_enabled = [
            r["name"] for r in catalog.load_all() if r["kind"] == "shell-enabled"
        ]
        self.assertEqual(
            shell_enabled,
            ["lab-runner"],
            "lab-runner is the only documented shell-enabled OCI exception",
        )


if __name__ == "__main__":
    unittest.main()
