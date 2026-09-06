"""Regression checks for the Renovate BuildStream tracking pipeline.

Renovate cannot compute a BuildStream `ref:` (a sha256 for `tar`/`remote`
sources, a commit for `git_repo` sources) and `bst source track` cannot
discover a version hidden behind a variable-built URL. The repo wires both
together: a single generic `custom.regex` manager annotates any pin with
`# renovate: datasource=... depName=...` (see b1f57e1, "track every upstream
package automatically"), and `.github/workflows/refresh-bst-refs.yml`
recomputes the accompanying ref on Renovate's own PRs before they can merge.

These tests guard that pipeline stays wired end to end: the manager still
matches real annotations in the tree, the digest/ref is never something
Renovate itself claims to capture, and the automatic ref-refresh + no-automerge
safety net that makes a generic annotation on an archive/remote source safe is
still in place.
"""

from pathlib import Path
import json
import re
import unittest

import yaml


ROOT = Path(__file__).parents[1]


def _custom_regex_manager():
    config = json.loads((ROOT / "renovate.json").read_text())
    return config, config["customManagers"][0]


class RenovateAtomicTests(unittest.TestCase):
    def test_manager_captures_datasource_depname_and_version(self):
        _, manager = _custom_regex_manager()
        pattern = re.compile(manager["matchStrings"][0].replace("(?<", "(?P<"))

        # Sample a handful of real annotated pins across the tree, including a
        # git_repo source (buildah) and remote/archive sources (yq, falco).
        # None of these carry a ref/digest capture: the manager only ever
        # claims to know the version, never the sha256/commit.
        cases = {
            "elements/buildah/buildah.bst": {
                "datasource": "github-tags",
                "depName": "containers/buildah",
                "currentValue": "v1.45.0",
            },
            "elements/lab-runner/yq.bst": {
                "datasource": "github-releases",
                "depName": "mikefarah/yq",
            },
            "elements/falco/falco.bst": {
                "datasource": "github-releases",
                "depName": "falcosecurity/falco",
                "currentValue": "0.44.1",
            },
        }
        for rel_path, expected in cases.items():
            element = (ROOT / rel_path).read_text()
            match = pattern.search(element)
            self.assertIsNotNone(match, f"no renovate annotation matched in {rel_path}")
            for key, value in expected.items():
                self.assertEqual(match.group(key), value, f"{rel_path}: {key}")

        self.assertNotIn("currentDigest", pattern.groupindex)

    def test_manager_is_scoped_to_bst_and_justfile(self):
        config, manager = _custom_regex_manager()

        self.assertEqual(config["enabledManagers"], ["github-actions", "custom.regex"])
        self.assertEqual(
            manager["managerFilePatterns"],
            ["/\\.bst$/", "/^Justfile$/"],
        )
        # datasource/versioning are read per-annotation from the matched
        # comment, not fixed on the manager (that would force every pin to be
        # the same kind of upstream package, which is no longer true).
        self.assertNotIn("datasourceTemplate", manager)
        self.assertIn("(?<datasource>\\S+)", manager["matchStrings"][0])
        self.assertIn("(?<depName>\\S+)", manager["matchStrings"][0])

    def test_custom_regex_bumps_never_automerge(self):
        """Every generic annotation match is gated behind human/CI review.

        A generic annotation can land on an archive/remote source whose ref
        Renovate cannot verify; that's only safe because these bumps never
        automerge and refresh-bst-refs.yml recomputes the ref first.
        """
        config, _ = _custom_regex_manager()
        rules = [
            rule
            for rule in config["packageRules"]
            if rule.get("matchManagers") == ["custom.regex"]
        ]
        self.assertTrue(rules, "no packageRule scopes custom.regex")
        self.assertTrue(
            all(rule.get("automerge") is False for rule in rules),
            "a custom.regex packageRule allows automerge",
        )

    def test_refresh_workflow_recomputes_refs_for_bst_changes(self):
        """refresh-bst-refs.yml must still run `bst source track` on PRs
        touching elements/*.bst, which is what makes a generic annotation on
        an archive/remote source (no ref capture) safe to merge."""
        workflow_path = ROOT / ".github/workflows/refresh-bst-refs.yml"
        self.assertTrue(workflow_path.exists(), workflow_path)
        workflow = yaml.safe_load(workflow_path.read_text())

        on_key = True if True in workflow else "on"
        paths = workflow[on_key]["pull_request"]["paths"]
        self.assertTrue(
            any(re.search(r"elements/.*\.bst", p) for p in paths),
            f"refresh-bst-refs.yml no longer watches elements/*.bst: {paths}",
        )

        steps = workflow["jobs"]["refresh"]["steps"]
        run_steps = " ".join(step.get("run", "") for step in steps)
        self.assertIn("bst source track", run_steps)


if __name__ == "__main__":
    unittest.main()
