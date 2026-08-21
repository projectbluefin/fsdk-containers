"""The catalog schema is the contract for an image record."""

from pathlib import Path
import sys
import unittest

ROOT = Path(__file__).parents[1]
sys.path.insert(0, str(ROOT / "scripts"))

import catalog  # noqa: E402


class SchemaTests(unittest.TestCase):
    def test_base_record_is_valid(self):
        record = catalog.load_record(ROOT / "catalog" / "base.yaml")
        self.assertEqual(record["name"], "base")
        self.assertEqual(record["kind"], "distroless")

    def test_missing_required_field_is_rejected(self):
        with self.assertRaises(catalog.CatalogError) as ctx:
            catalog.validate({"name": "broken"})
        self.assertIn("kind", str(ctx.exception))

    def test_unknown_field_is_rejected(self):
        record = {
            "name": "broken",
            "kind": "distroless",
            "description": "x",
            "entrypoint": ["/bin/true"],
            "smoke": {"args": ["--version"]},
            "size_ceiling_mib": 64,
            "stack": {"components": []},
            "nonsense": True,
        }
        with self.assertRaises(catalog.CatalogError):
            catalog.validate(record)

    def test_name_must_match_filename(self):
        with self.assertRaises(catalog.CatalogError) as ctx:
            catalog.load_record(ROOT / "catalog" / "base.yaml", expect_name="python")
        self.assertIn("filename", str(ctx.exception))

    def test_compose_exclude_is_canonical_by_default(self):
        record = catalog.load_record(ROOT / "catalog" / "base.yaml")
        self.assertEqual(catalog.compose_exclude(record), catalog.CANONICAL_EXCLUDE)

    def test_exclude_omit_requires_a_reason(self):
        record = {
            "name": "broken",
            "kind": "distroless",
            "description": "x",
            "entrypoint": ["/bin/true"],
            "smoke": {"args": ["--version"]},
            "size_ceiling_mib": 64,
            "stack": {"components": []},
            "compose": {"exclude_omit": [{"domain": "devel"}]},
        }
        with self.assertRaises(catalog.CatalogError):
            catalog.validate(record)


if __name__ == "__main__":
    unittest.main()
