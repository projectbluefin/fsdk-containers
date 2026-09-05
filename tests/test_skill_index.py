"""Unit coverage for scripts/generate_skill_index.py.

skill-catalog.yml only exercises this generator end-to-end via `--check`
against the committed docs. That proves the happy path on today's docs but
leaves every guard rail — missing front matter, missing required keys, an
entry_point that lies about its own path, the generated_at pinning that keeps
`--check` from failing on calendar drift — completely unverified. These tests
drive those paths directly against a synthetic skills tree.
"""

import contextlib
import io
import json
from pathlib import Path
import sys
import tempfile
import unittest
from unittest import mock

ROOT = Path(__file__).parents[1]
sys.path.insert(0, str(ROOT / "scripts"))

import generate_skill_index as gsi  # noqa: E402


SCHEMA_TEXT = (ROOT / "docs" / "skills" / "index.schema.json").read_text()


def front_matter(**overrides) -> dict:
    fm = {
        "id": "example-skill",
        "name": "example-skill",
        "one_line_purpose": "Do the example thing.",
        "entry_point": "docs/skills/example-skill.md",
        "category": "meta",
        "status": "active",
        "tags": ["example"],
        "description": "A description.",
        "version": 1,
        "last_updated": "2026-01-01",
    }
    fm.update(overrides)
    return fm


def render_doc(fm: dict, body: str = "\nBody text.\n") -> str:
    lines = ["---"]
    for key, value in fm.items():
        lines.append(f"{key}: {json.dumps(value)}")
    lines.append("---")
    return "\n".join(lines) + "\n" + body


class SkillsTreeTestCase(unittest.TestCase):
    """Point the generator's module-level paths at a throwaway skills tree."""

    def setUp(self):
        self._tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self._tmp.cleanup)
        self.root = Path(self._tmp.name)
        self.skills = self.root / "docs" / "skills"
        self.skills.mkdir(parents=True)
        (self.skills / "index.schema.json").write_text(SCHEMA_TEXT)

        for name, value in (
            ("REPO_ROOT", self.root),
            ("SKILLS_DIR", self.skills),
            ("SCHEMA_PATH", self.skills / "index.schema.json"),
            ("INDEX_PATH", self.skills / "index.json"),
        ):
            patcher = mock.patch.object(gsi, name, value)
            patcher.start()
            self.addCleanup(patcher.stop)

    def write_skill(self, rel: str, **overrides) -> Path:
        path = self.skills / rel
        path.parent.mkdir(parents=True, exist_ok=True)
        fm = front_matter(entry_point=f"docs/skills/{rel}", **overrides)
        path.write_text(render_doc(fm))
        return path


class ParseFrontMatterTests(SkillsTreeTestCase):
    def test_parses_the_leading_yaml_block(self):
        path = self.write_skill("example-skill.md")
        self.assertEqual(gsi.parse_front_matter(path)["id"], "example-skill")

    def test_a_doc_with_no_front_matter_is_rejected(self):
        path = self.skills / "bare.md"
        path.write_text("# No front matter here\n")
        with self.assertRaisesRegex(ValueError, "no YAML front matter"):
            gsi.parse_front_matter(path)

    def test_front_matter_must_be_delimited_at_the_very_top(self):
        """A `---` block after prose is not front matter and must not count."""
        path = self.skills / "late.md"
        path.write_text("# Title\n\n---\nid: late\n---\n")
        with self.assertRaisesRegex(ValueError, "no YAML front matter"):
            gsi.parse_front_matter(path)

    def test_non_mapping_front_matter_is_rejected(self):
        path = self.skills / "listy.md"
        path.write_text("---\n- one\n- two\n---\nbody\n")
        with self.assertRaisesRegex(ValueError, "did not parse to a mapping"):
            gsi.parse_front_matter(path)


class BuildSkillEntryTests(SkillsTreeTestCase):
    def test_builds_an_entry_from_valid_front_matter(self):
        path = self.write_skill("example-skill.md")
        entry = gsi.build_skill_entry(path)
        self.assertEqual(entry["id"], "example-skill")
        self.assertEqual(entry["entry_point"], "docs/skills/example-skill.md")
        self.assertEqual(entry["tags"], ["example"])
        self.assertNotIn("doc_type", entry)

    def test_version_and_last_updated_are_coerced_to_strings(self):
        """YAML happily yields an int version or a date object — the schema
        demands strings, so the generator must stringify both."""
        path = self.write_skill("example-skill.md", version=2)
        entry = gsi.build_skill_entry(path)
        self.assertEqual(entry["version"], "2")
        self.assertIsInstance(entry["last_updated"], str)

    def test_description_whitespace_is_collapsed(self):
        path = self.write_skill(
            "example-skill.md",
            description="wrapped\nacross   several\nlines",
        )
        self.assertEqual(
            gsi.build_skill_entry(path)["description"],
            "wrapped across several lines",
        )

    def test_metadata_type_becomes_doc_type(self):
        path = self.write_skill("example-skill.md", metadata={"type": "runbook"})
        self.assertEqual(gsi.build_skill_entry(path)["doc_type"], "runbook")

    def test_absent_metadata_type_does_not_add_doc_type(self):
        path = self.write_skill("example-skill.md", metadata={"owner": "ci"})
        self.assertNotIn("doc_type", gsi.build_skill_entry(path))

    def test_null_metadata_block_is_tolerated(self):
        """`metadata:` with nothing under it parses as None, not a dict."""
        path = self.skills / "example-skill.md"
        lines = [f"{k}: {json.dumps(v)}" for k, v in front_matter().items()]
        path.write_text("---\n" + "\n".join(lines) + "\nmetadata:\n---\n\nBody\n")
        self.assertNotIn("doc_type", gsi.build_skill_entry(path))

    def test_missing_required_keys_are_named_in_the_error(self):
        path = self.skills / "example-skill.md"
        fm = front_matter()
        del fm["category"]
        del fm["tags"]
        path.write_text(render_doc(fm))
        with self.assertRaises(ValueError) as ctx:
            gsi.build_skill_entry(path)
        self.assertIn("category", str(ctx.exception))
        self.assertIn("tags", str(ctx.exception))

    def test_entry_point_must_match_the_real_path(self):
        """A copy-pasted entry_point silently sends agents to another file."""
        path = self.skills / "example-skill.md"
        path.write_text(render_doc(front_matter(entry_point="docs/skills/other.md")))
        with self.assertRaisesRegex(ValueError, "does not match actual path"):
            gsi.build_skill_entry(path)


class FindSkillFilesTests(SkillsTreeTestCase):
    def test_collects_flat_docs_and_per_directory_skill_files(self):
        self.write_skill("beta.md", id="beta")
        self.write_skill("alpha.md", id="alpha")
        self.write_skill("nested/SKILL.md", id="nested")
        found = [p.relative_to(self.skills).as_posix() for p in gsi.find_skill_files()]
        self.assertEqual(found, ["alpha.md", "beta.md", "nested/SKILL.md"])

    def test_index_md_is_never_treated_as_a_skill(self):
        self.write_skill("alpha.md", id="alpha")
        (self.skills / "index.md").write_text("# generated mirror\n")
        found = [p.name for p in gsi.find_skill_files()]
        self.assertEqual(found, ["alpha.md"])

    def test_non_skill_markdown_inside_a_skill_directory_is_ignored(self):
        self.write_skill("nested/SKILL.md", id="nested")
        (self.skills / "nested" / "references.md").write_text("# notes\n")
        found = [p.relative_to(self.skills).as_posix() for p in gsi.find_skill_files()]
        self.assertEqual(found, ["nested/SKILL.md"])


class BuildCatalogTests(SkillsTreeTestCase):
    def test_skills_are_sorted_by_id_not_by_filename(self):
        self.write_skill("zzz-file.md", id="aaa-skill")
        self.write_skill("aaa-file.md", id="zzz-skill")
        catalog = gsi.build_catalog()
        self.assertEqual([s["id"] for s in catalog["skills"]], ["aaa-skill", "zzz-skill"])
        self.assertEqual(catalog["schema_version"], gsi.SCHEMA_VERSION)


class GeneratedAtPinningTests(SkillsTreeTestCase):
    def test_unchanged_content_keeps_the_committed_date(self):
        catalog = {"generated_at": "2026-08-27", "schema_version": "1.0", "skills": []}
        existing = {"generated_at": "2024-01-02", "schema_version": "1.0", "skills": []}
        gsi.pin_unchanged_generated_at(catalog, existing)
        self.assertEqual(catalog["generated_at"], "2024-01-02")

    def test_changed_skills_advance_the_date(self):
        catalog = {"generated_at": "2026-08-27", "schema_version": "1.0", "skills": [{"id": "a"}]}
        existing = {"generated_at": "2024-01-02", "schema_version": "1.0", "skills": []}
        gsi.pin_unchanged_generated_at(catalog, existing)
        self.assertEqual(catalog["generated_at"], "2026-08-27")

    def test_schema_version_bump_advances_the_date(self):
        catalog = {"generated_at": "2026-08-27", "schema_version": "2.0", "skills": []}
        existing = {"generated_at": "2024-01-02", "schema_version": "1.0", "skills": []}
        gsi.pin_unchanged_generated_at(catalog, existing)
        self.assertEqual(catalog["generated_at"], "2026-08-27")

    def test_absent_existing_catalog_is_a_no_op(self):
        catalog = {"generated_at": "2026-08-27", "schema_version": "1.0", "skills": []}
        gsi.pin_unchanged_generated_at(catalog, None)
        self.assertEqual(catalog["generated_at"], "2026-08-27")


class LoadExistingCatalogTests(SkillsTreeTestCase):
    def test_missing_index_returns_none(self):
        self.assertIsNone(gsi.load_existing_catalog())

    def test_corrupt_index_returns_none_instead_of_raising(self):
        gsi.INDEX_PATH.write_text("{ not json")
        self.assertIsNone(gsi.load_existing_catalog())

    def test_valid_index_is_returned(self):
        gsi.INDEX_PATH.write_text(json.dumps({"schema_version": "1.0", "skills": []}))
        self.assertEqual(gsi.load_existing_catalog()["schema_version"], "1.0")


class ValidateCatalogTests(SkillsTreeTestCase):
    def test_a_conforming_catalog_passes(self):
        self.write_skill("example-skill.md")
        gsi.validate_catalog(gsi.build_catalog())

    def test_a_schema_violation_exits_nonzero_and_reports_the_location(self):
        catalog = gsi.build_catalog()
        catalog["skills"] = [{"id": "Not Kebab Case"}]
        err = io.StringIO()
        with contextlib.redirect_stderr(err), self.assertRaises(SystemExit) as ctx:
            gsi.validate_catalog(catalog)
        self.assertEqual(ctx.exception.code, 1)
        self.assertIn("schema error at", err.getvalue())


class RenderMarkdownTests(SkillsTreeTestCase):
    def test_table_links_are_relative_to_the_skills_directory(self):
        self.write_skill("nested/SKILL.md", id="nested")
        md = gsi.render_markdown(gsi.build_catalog())
        self.assertIn("[nested](nested/SKILL.md)", md)
        self.assertNotIn("(docs/skills/", md)

    def test_header_reports_the_skill_count_and_schema_version(self):
        self.write_skill("alpha.md", id="alpha")
        self.write_skill("beta.md", id="beta")
        md = gsi.render_markdown(gsi.build_catalog())
        self.assertIn("schema 1.0 · 2 skills", md)
        self.assertIn("| id | category | status | one-line purpose |", md)


class MainTests(SkillsTreeTestCase):
    def _run(self, *argv) -> tuple[int, str, str]:
        out, err = io.StringIO(), io.StringIO()
        with mock.patch.object(sys, "argv", ["generate_skill_index.py", *argv]):
            with contextlib.redirect_stdout(out), contextlib.redirect_stderr(err):
                code = gsi.main()
        return code, out.getvalue(), err.getvalue()

    def test_write_then_check_round_trips(self):
        self.write_skill("example-skill.md")
        self.assertEqual(self._run("--write")[0], 0)
        self.assertTrue(gsi.INDEX_PATH.exists())
        self.assertTrue((self.skills / "index.md").exists())
        self.assertEqual(self._run("--check")[0], 0)

    def test_check_fails_when_the_index_is_stale(self):
        self.write_skill("example-skill.md")
        self._run("--write")
        self.write_skill("late-arrival.md", id="late-arrival")
        code, _, err = self._run("--check")
        self.assertEqual(code, 1)
        self.assertIn("index.json is stale", err)

    def test_check_fails_when_only_the_markdown_mirror_is_stale(self):
        """index.md drifting alone must still fail the gate."""
        self.write_skill("example-skill.md")
        self._run("--write")
        (self.skills / "index.md").write_text("# hand-edited\n")
        code, _, err = self._run("--check")
        self.assertEqual(code, 1)
        self.assertIn("index.md is stale", err)

    def test_a_malformed_skill_doc_fails_with_a_message_not_a_traceback(self):
        (self.skills / "broken.md").write_text("# no front matter\n")
        code, _, err = self._run("--check")
        self.assertEqual(code, 1)
        self.assertIn("error:", err)

    def test_write_is_idempotent_and_does_not_advance_generated_at(self):
        self.write_skill("example-skill.md")
        self._run("--write")
        gsi.INDEX_PATH.write_text(
            gsi.INDEX_PATH.read_text().replace(
                json.loads(gsi.INDEX_PATH.read_text())["generated_at"], "2020-01-01"
            )
        )
        self._run("--write")
        self.assertEqual(json.loads(gsi.INDEX_PATH.read_text())["generated_at"], "2020-01-01")


class CommittedCatalogTests(unittest.TestCase):
    """The real docs/skills tree must keep satisfying its own schema."""

    def test_every_committed_skill_builds_and_validates(self):
        catalog = gsi.build_catalog()
        self.assertTrue(catalog["skills"], "expected at least one skill doc")
        gsi.validate_catalog(catalog)

    def test_committed_skill_ids_are_unique(self):
        ids = [s["id"] for s in gsi.build_catalog()["skills"]]
        self.assertEqual(sorted(ids), sorted(set(ids)))


if __name__ == "__main__":
    unittest.main()
