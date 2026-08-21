"""Every published image has a record, and every record has an image."""

import json
from pathlib import Path
import sys
import unittest

import yaml

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


def _element(*parts):
    return yaml.safe_load((ROOT / "elements" / Path(*parts)).read_text())


class RecordsDescribeRealityTests(unittest.TestCase):
    """A record that lies about its elements would silently change an image
    the moment the generator takes ownership. Assert agreement first."""

    def test_stack_depends_match_the_record(self):
        for record in catalog.load_all():
            with self.subTest(image=record["name"]):
                name = record["name"]
                committed = _element(name, f"{name}-stack.bst")
                expected = []
                if record["stack"].get("base"):
                    expected.append(record["stack"]["base"])
                expected += record["stack"]["components"]
                expected += record["stack"].get("extra_depends", [])
                self.assertEqual(
                    sorted(committed["depends"]),
                    sorted(expected),
                    f"{name}-stack.bst depends do not match catalog/{name}.yaml",
                )

    def test_compose_exclude_matches_the_record(self):
        for record in catalog.load_all():
            with self.subTest(image=record["name"]):
                name = record["name"]
                committed = _element(name, f"{name}-runtime.bst")
                self.assertEqual(
                    sorted(committed["config"]["exclude"]),
                    sorted(catalog.compose_exclude(record)),
                    f"{name}-runtime.bst exclude set does not match "
                    f"catalog/{name}.yaml; declare the difference in "
                    f"compose.exclude_omit with a reason",
                )

    def test_slim_extra_matches_the_committed_oci_element(self):
        for record in catalog.load_all():
            with self.subTest(image=record["name"]):
                name = record["name"]
                committed = _element("oci", f"{name}.bst")
                commands = committed["config"]["commands"]
                extras = [
                    c for c in commands
                    if not c.startswith("%{slim-")
                    and "build-oci" not in c
                    and "initial_scripts" not in c
                ]
                declared = record.get("slim", {}).get("extra")
                if declared is None:
                    self.assertEqual(
                        extras, [],
                        f"oci/{name}.bst has extra slim commands not declared "
                        f"in catalog/{name}.yaml slim.extra",
                    )
                else:
                    self.assertEqual(
                        [c.strip() for c in extras],
                        [declared.strip()],
                        f"catalog/{name}.yaml slim.extra is not byte-equal to "
                        f"oci/{name}.bst",
                    )


if __name__ == "__main__":
    unittest.main()
