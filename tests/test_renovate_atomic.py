"""Regression checks for atomic BuildStream Renovate metadata."""

from pathlib import Path
import json
import re
import unittest


ROOT = Path(__file__).parents[1]


class RenovateAtomicTests(unittest.TestCase):
    def test_manager_captures_selector_and_commit_ref(self):
        config = json.loads((ROOT / "renovate.json").read_text())
        manager = config["customManagers"][0]
        pattern = re.compile(
            manager["matchStrings"][0].replace("(?<", "(?P<")
        )
        element = (ROOT / "elements/buildah/buildah.bst").read_text()
        match = pattern.search(element)

        self.assertIsNotNone(match)
        self.assertEqual(match.group("currentValue"), "v1.45.0")
        self.assertEqual(
            match.group("currentDigest"),
            "b459120c69f877227039ca6ddb8131c11f6e641d",
        )
        self.assertEqual(manager["datasourceTemplate"], "git-refs")

    def test_unmanaged_archive_sources_have_no_renovate_annotation(self):
        for path in (ROOT / "elements").rglob("*.bst"):
            text = path.read_text()
            if "kind: remote" in text and "# renovate:" in text:
                self.fail(
                    f"archive/remote source must not use generic Renovate metadata: {path}"
                )

    def test_manager_is_scoped_to_git_refs_and_buildah(self):
        config = json.loads((ROOT / "renovate.json").read_text())
        manager = config["customManagers"][0]

        self.assertEqual(config["enabledManagers"], ["github-actions", "custom.regex"])
        self.assertEqual(
            manager["managerFilePatterns"],
            ["/(^|/)elements/buildah/buildah\\.bst$/"],
        )
        self.assertEqual(manager["datasourceTemplate"], "git-refs")
        self.assertIn("(?<currentDigest>[0-9a-f]{40})", manager["matchStrings"][0])


if __name__ == "__main__":
    unittest.main()
