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


if __name__ == "__main__":
    unittest.main()
