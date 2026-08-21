"""Generated elements must be semantically identical to committed ones."""

from pathlib import Path
import sys
import unittest

import yaml

ROOT = Path(__file__).parents[1]
sys.path.insert(0, str(ROOT / "scripts"))

import catalog  # noqa: E402
import generate_image_elements as gen  # noqa: E402


class ComposeGenerationTests(unittest.TestCase):
    def test_generated_compose_matches_committed(self):
        for record in catalog.load_all():
            with self.subTest(image=record["name"]):
                name = record["name"]
                committed_path = ROOT / "elements" / name / f"{name}-runtime.bst"
                committed = yaml.safe_load(committed_path.read_text())
                generated = yaml.safe_load(gen.render_compose(record))
                self.assertEqual(generated["kind"], committed["kind"])
                self.assertEqual(
                    generated["build-depends"], committed["build-depends"]
                )
                self.assertEqual(
                    sorted(generated["config"]["exclude"]),
                    sorted(committed["config"]["exclude"]),
                )

    def test_generated_compose_is_valid_yaml_with_a_header(self):
        record = catalog.load_record(ROOT / "catalog" / "base.yaml")
        text = gen.render_compose(record)
        self.assertIn("DO NOT EDIT", text)
        self.assertIn("catalog/base.yaml", text)
        self.assertIsInstance(yaml.safe_load(text), dict)

    def test_check_mode_passes_on_a_clean_tree(self):
        self.assertEqual(gen.check(), [])


class StackGenerationTests(unittest.TestCase):
    def test_generated_stack_matches_committed(self):
        for record in catalog.load_all():
            with self.subTest(image=record["name"]):
                name = record["name"]
                committed = yaml.safe_load(
                    (ROOT / "elements" / name / f"{name}-stack.bst").read_text()
                )
                generated = yaml.safe_load(gen.render_stack(record))
                self.assertEqual(generated["kind"], "stack")
                # ORDER-SENSITIVE: sorting here masked a real cache-key change.
                self.assertEqual(generated["depends"], committed["depends"])

    def test_notes_are_carried_into_the_generated_stack(self):
        record = catalog.load_record(ROOT / "catalog" / "base.yaml")
        text = gen.render_stack(record)
        self.assertIn("runtime-gnu is a deliberate dependency", text)


SHARED_LABELS = {
    "org.opencontainers.image.vendor": "Project Bluefin",
    "org.opencontainers.image.licenses": "Apache-2.0",
    "org.opencontainers.image.url": "https://github.com/projectbluefin/fsdk-containers",
    "org.opencontainers.image.source": "https://github.com/projectbluefin/fsdk-containers",
    "io.artifacthub.package.license": "Apache-2.0",
    "io.artifacthub.package.category": "integration-delivery",
}


class OciGenerationTests(unittest.TestCase):
    def test_generated_oci_matches_committed_build_depends(self):
        for record in catalog.load_all():
            with self.subTest(image=record["name"]):
                name = record["name"]
                committed = yaml.safe_load(
                    (ROOT / "elements" / "oci" / f"{name}.bst").read_text()
                )
                generated = yaml.safe_load(gen.render_oci(record))
                self.assertEqual(generated["kind"], "script")
                self.assertEqual(
                    generated["build-depends"], committed["build-depends"]
                )
                self.assertEqual(generated["variables"], committed["variables"])

    def test_slim_recipe_is_always_the_first_command(self):
        for record in catalog.load_all():
            with self.subTest(image=record["name"]):
                generated = yaml.safe_load(gen.render_oci(record))
                first = generated["config"]["commands"][0]
                expected = (
                    "%{slim-shell-enabled-commands}"
                    if record["kind"] == "shell-enabled"
                    else "%{slim-distroless-commands}"
                )
                self.assertEqual(first, expected)

    def test_every_image_carries_the_shared_labels(self):
        for record in catalog.load_all():
            with self.subTest(image=record["name"]):
                text = gen.render_oci(record)
                for key, value in SHARED_LABELS.items():
                    self.assertIn(f"'{key}': '{value}'", text)

    def test_slim_extra_is_emitted_verbatim(self):
        record = catalog.load_record(ROOT / "catalog" / "python.yaml")
        generated = yaml.safe_load(gen.render_oci(record))
        commands = generated["config"]["commands"]
        self.assertIn(
            record["slim"]["extra"].strip(),
            [c.strip() for c in commands],
        )


if __name__ == "__main__":
    unittest.main()
