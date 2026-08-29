"""Coverage for catalog.load_record's rejection paths.

test_catalog_schema.py and test_catalog_conformance.py exercise the happy path
against committed records. The branches that reject a missing file, a
non-mapping document, a filename that disagrees with the record name, and a
caller-supplied expected name were never executed. Those are the branches that
stop a silently-misfiled record from generating elements for the wrong image.
"""

from pathlib import Path
import sys
import tempfile
import unittest

import yaml

ROOT = Path(__file__).parents[1]
sys.path.insert(0, str(ROOT / "scripts"))

import catalog  # noqa: E402


class LoadRecordTestCase(unittest.TestCase):
    def setUp(self):
        self._tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self._tmp.cleanup)
        self.dir = Path(self._tmp.name)
        self.record = yaml.safe_load((ROOT / "catalog" / "base.yaml").read_text())

    def write_record(self, filename, record=None):
        path = self.dir / filename
        path.write_text(yaml.safe_dump(record if record is not None else self.record))
        return path


class MissingAndMalformedTests(LoadRecordTestCase):
    def test_missing_record_names_the_path(self):
        missing = self.dir / "nope.yaml"

        with self.assertRaises(catalog.CatalogError) as raised:
            catalog.load_record(missing)

        self.assertIn("no such record", str(raised.exception))
        self.assertIn("nope.yaml", str(raised.exception))

    def test_a_yaml_list_is_not_a_record(self):
        path = self.dir / "list.yaml"
        path.write_text("- one\n- two\n")

        with self.assertRaises(catalog.CatalogError) as raised:
            catalog.load_record(path)

        self.assertIn("must be a YAML mapping", str(raised.exception))

    def test_an_empty_document_is_not_a_record(self):
        path = self.dir / "empty.yaml"
        path.write_text("")

        with self.assertRaises(catalog.CatalogError):
            catalog.load_record(path)

    def test_a_scalar_document_is_not_a_record(self):
        path = self.dir / "scalar.yaml"
        path.write_text("just-a-string\n")

        with self.assertRaises(catalog.CatalogError) as raised:
            catalog.load_record(path)

        self.assertIn("must be a YAML mapping", str(raised.exception))


class NameAgreementTests(LoadRecordTestCase):
    def test_record_name_must_match_the_filename_stem(self):
        path = self.write_record("misfiled.yaml")

        with self.assertRaises(catalog.CatalogError) as raised:
            catalog.load_record(path)

        message = str(raised.exception)
        self.assertIn("does not match filename stem", message)
        self.assertIn("misfiled", message)

    def test_expect_name_rejects_a_record_for_a_different_image(self):
        path = self.write_record(f"{self.record['name']}.yaml")

        with self.assertRaises(catalog.CatalogError) as raised:
            catalog.load_record(path, expect_name="some-other-image")

        self.assertIn("expected record named", str(raised.exception))

    def test_expect_name_accepts_the_matching_record(self):
        path = self.write_record(f"{self.record['name']}.yaml")

        loaded = catalog.load_record(path, expect_name=self.record["name"])

        self.assertEqual(loaded["name"], self.record["name"])

    def test_a_string_path_is_accepted(self):
        path = self.write_record(f"{self.record['name']}.yaml")

        loaded = catalog.load_record(str(path))

        self.assertEqual(loaded["name"], self.record["name"])


class ValidateTests(LoadRecordTestCase):
    def test_schema_violation_is_reported_with_the_offending_field(self):
        broken = dict(self.record)
        broken["kind"] = "not-a-real-kind"

        with self.assertRaises(catalog.CatalogError) as raised:
            catalog.validate(broken)

        self.assertIn("invalid record", str(raised.exception))
        self.assertIn("kind", str(raised.exception))

    def test_shell_probe_requires_a_shell_enabled_image(self):
        record = dict(self.record)
        record["kind"] = "distroless"
        record["smoke"] = {"args": ["--version"], "shell_probe": "test -x /bin/sh"}

        with self.assertRaises(catalog.CatalogError) as raised:
            catalog.validate(record)

        self.assertIn("shell_probe requires kind: shell-enabled", str(raised.exception))

    def test_validate_returns_the_record_it_accepted(self):
        self.assertIs(catalog.validate(self.record), self.record)


class ComposeExcludeTests(unittest.TestCase):
    def test_a_record_with_no_omissions_gets_the_canonical_set(self):
        self.assertEqual(
            catalog.compose_exclude({"name": "demo"}), catalog.CANONICAL_EXCLUDE
        )

    def test_declared_omissions_are_removed_and_order_is_preserved(self):
        record = {"name": "demo", "compose": {"exclude_omit": [{"domain": "shells"}]}}

        excluded = catalog.compose_exclude(record)

        self.assertNotIn("shells", excluded)
        self.assertEqual(
            excluded, [d for d in catalog.CANONICAL_EXCLUDE if d != "shells"]
        )

    def test_an_unknown_omission_domain_changes_nothing(self):
        record = {"name": "demo", "compose": {"exclude_omit": [{"domain": "bogus"}]}}

        self.assertEqual(catalog.compose_exclude(record), catalog.CANONICAL_EXCLUDE)

    def test_the_canonical_set_is_not_mutated_by_a_call(self):
        before = list(catalog.CANONICAL_EXCLUDE)

        catalog.compose_exclude(
            {"name": "demo", "compose": {"exclude_omit": [{"domain": "doc"}]}}
        )

        self.assertEqual(catalog.CANONICAL_EXCLUDE, before)


if __name__ == "__main__":
    unittest.main()
