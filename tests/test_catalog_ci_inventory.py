"""The CI workflow inventory is documentation, so prove the documentation is complete.

``docs/skills/ci-tooling/references/workflow-structure.md`` is the skill an agent
or contributor reads to learn what this repository's pipeline is. It presents
itself as an inventory: a table for the publication lane, a table for the
supporting workflows, a table for jobs. Nothing proved the inventory covered
``.github/workflows/``, and it did not -- ``image-catalog.yml`` (the merge gate
for the whole ``catalog/`` generation contract and the only workflow that runs
the Python suite), ``refresh-bst-refs.yml`` (the only workflow that pushes to a
pull-request branch), and ``skill-catalog.yml`` appeared nowhere in it.

That is the same fail-open shape ``tests/test_catalog_gate_coverage.py`` closed
for test modules: an allowlist maintained by hand that nobody checks. A reader
who trusts the document concludes the undocumented workflow does not exist, and
a privileged workflow can be added with no signal at all.

These tests are a two-way ratchet over the inventory:

* every ``.github/workflows/*.yml`` and every ``.github/actions/*/action.yml``
  must be named somewhere in the reference document, and
* every workflow filename the document names must still exist on disk, so a
  deleted workflow cannot leave a table row pointing at nothing.

They assert nothing about what a workflow *does*; the description is a human's
job. Only the existence of an entry is mechanical, so only that is gated.
"""

from pathlib import Path
import re
import unittest


ROOT = Path(__file__).parents[1]
WORKFLOW_DIR = ROOT / ".github" / "workflows"
ACTION_DIR = ROOT / ".github" / "actions"
REFERENCE = (
    ROOT / "docs" / "skills" / "ci-tooling" / "references" / "workflow-structure.md"
)

# Workflow files this repository does not own. `reusable-renovate.yml` lives in
# projectbluefin/actions and is named here only as the callee of the thin
# caller `validate-renovate.yml`; requiring a local file for it would be wrong.
FOREIGN_WORKFLOWS = frozenset({"reusable-renovate.yml"})

# A bare workflow filename as the document writes it in code spans, either on
# its own (`build.yml`) or path-qualified (`.github/workflows/brew-nspawn.yml`).
DOCUMENTED_WORKFLOW_RE = re.compile(
    r"`(?:\.github/workflows/)?([A-Za-z0-9._-]+\.ya?ml)`"
)


def _doc_text():
    return REFERENCE.read_text()


def _local_workflows():
    return sorted(
        p.name
        for p in list(WORKFLOW_DIR.glob("*.yml")) + list(WORKFLOW_DIR.glob("*.yaml"))
    )


def _composite_actions():
    """Directory names under .github/actions that hold an action definition."""
    if not ACTION_DIR.is_dir():
        return []
    return sorted(
        p.name
        for p in ACTION_DIR.iterdir()
        if (p / "action.yml").exists() or (p / "action.yaml").exists()
    )


def _documented_workflows(text):
    return {m.group(1) for m in DOCUMENTED_WORKFLOW_RE.finditer(text)}


class WorkflowInventoryTests(unittest.TestCase):
    def test_reference_document_exists(self):
        self.assertTrue(
            REFERENCE.exists(),
            f"{REFERENCE.relative_to(ROOT)} is the documented CI inventory and is "
            "missing; this gate has nothing to check",
        )

    def test_every_workflow_is_documented(self):
        workflows = _local_workflows()
        self.assertTrue(workflows, "no workflows found under .github/workflows")

        documented = _documented_workflows(_doc_text())
        undocumented = sorted(set(workflows) - documented)
        self.assertEqual(
            [],
            undocumented,
            "workflow(s) absent from "
            f"{REFERENCE.relative_to(ROOT)}: {', '.join(undocumented)}. "
            "Add a row describing the trigger and purpose -- an undocumented "
            "workflow is invisible to everyone who reads the ci-tooling skill.",
        )

    def test_every_composite_action_is_documented(self):
        text = _doc_text()
        missing = [
            name
            for name in _composite_actions()
            if f"`.github/actions/{name}`" not in text
        ]
        self.assertEqual(
            [],
            missing,
            "composite action(s) absent from "
            f"{REFERENCE.relative_to(ROOT)}: {', '.join(missing)}. "
            "Reference them as `.github/actions/<name>`.",
        )

    def test_every_documented_workflow_still_exists(self):
        documented = _documented_workflows(_doc_text()) - FOREIGN_WORKFLOWS
        on_disk = set(_local_workflows())
        stale = sorted(documented - on_disk)
        self.assertEqual(
            [],
            stale,
            f"{REFERENCE.relative_to(ROOT)} names workflow file(s) that do not "
            f"exist: {', '.join(stale)}. Remove the entry, or add the file to "
            "FOREIGN_WORKFLOWS if it is owned by another repository.",
        )

    def test_foreign_workflow_allowlist_is_all_still_referenced(self):
        """A ratchet: an allowlist entry nobody names is dead weight."""
        documented = _documented_workflows(_doc_text())
        unused = sorted(FOREIGN_WORKFLOWS - documented)
        self.assertEqual(
            [],
            unused,
            "FOREIGN_WORKFLOWS entr(ies) no longer named by "
            f"{REFERENCE.relative_to(ROOT)}: {', '.join(unused)}. Drop them.",
        )


if __name__ == "__main__":
    unittest.main()
