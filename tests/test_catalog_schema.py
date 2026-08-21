"""The catalog schema is the contract for an image record."""

from pathlib import Path
import sys
import unittest

ROOT = Path(__file__).parents[1]
sys.path.insert(0, str(ROOT / "scripts"))

import catalog  # noqa: E402


def valid_record(**overrides):
    """A minimal record that passes validation.

    Negative tests start from this and change exactly one thing, so a test can
    only pass for the reason it names. An earlier draft used
    description: "x", which independently violated the schema's minLength and
    made three negative tests pass vacuously.
    """
    record = {
        "name": "probe",
        "kind": "distroless",
        "description": "A valid record used as a negative-test baseline",
        "size_ceiling_mib": 64,
        "stack": {"components": []},
    }
    record.update(overrides)
    return record


class SchemaTests(unittest.TestCase):
    def test_the_baseline_fixture_is_actually_valid(self):
        """Guards every negative test below: if this fails, they prove nothing."""
        self.assertEqual(catalog.validate(valid_record())["name"], "probe")

    def test_base_record_is_valid(self):
        record = catalog.load_record(ROOT / "catalog" / "base.yaml")
        self.assertEqual(record["name"], "base")
        self.assertEqual(record["kind"], "distroless")

    def test_missing_required_field_is_rejected(self):
        record = valid_record()
        del record["kind"]
        with self.assertRaises(catalog.CatalogError) as ctx:
            catalog.validate(record)
        self.assertIn("kind", str(ctx.exception))

    def test_unknown_field_is_rejected(self):
        with self.assertRaises(catalog.CatalogError):
            catalog.validate(valid_record(nonsense=True))

    def test_name_must_match_filename(self):
        with self.assertRaises(catalog.CatalogError) as ctx:
            catalog.load_record(ROOT / "catalog" / "base.yaml", expect_name="python")
        self.assertIn("filename", str(ctx.exception))

    def test_compose_exclude_is_canonical_by_default(self):
        record = catalog.load_record(ROOT / "catalog" / "base.yaml")
        self.assertEqual(catalog.compose_exclude(record), catalog.CANONICAL_EXCLUDE)

    def test_exclude_omit_requires_a_reason(self):
        record = valid_record(compose={"exclude_omit": [{"domain": "devel"}]})
        with self.assertRaises(catalog.CatalogError):
            catalog.validate(record)

    def test_shell_probe_is_rejected_on_a_distroless_record(self):
        record = valid_record(smoke={"args": [], "shell_probe": "true"})
        with self.assertRaises(catalog.CatalogError) as ctx:
            catalog.validate(record)
        self.assertIn("shell-enabled", str(ctx.exception))

    def test_an_empty_shell_probe_is_also_rejected(self):
        """Presence, not truthiness. An empty string is still a shell probe."""
        record = valid_record(smoke={"args": [], "shell_probe": ""})
        with self.assertRaises(catalog.CatalogError):
            catalog.validate(record)

    def test_shell_probe_is_allowed_on_a_shell_enabled_record(self):
        record = valid_record(kind="shell-enabled", smoke={"args": [], "shell_probe": "true"})
        self.assertEqual(catalog.validate(record)["kind"], "shell-enabled")

    def test_a_record_may_omit_entrypoint_and_smoke(self):
        """base and static have neither today; the schema must not force them."""
        record = valid_record()
        self.assertNotIn("entrypoint", record)
        self.assertNotIn("smoke", record)
        catalog.validate(record)


if __name__ == "__main__":
    unittest.main()
