"""Protect the required queue checks from accidentally publishing images."""

from pathlib import Path
import os
import subprocess
import re
import unittest

import yaml


WORKFLOW = Path(__file__).resolve().parents[1] / ".github/workflows/build.yml"


def enabled(condition, event, any_oci=True, vm_guest=True):
    """Evaluate the workflow's simple event and changed-target conditions."""
    expression = condition.replace("always()", "True")
    values = {
        "github.event_name": event,
        "needs.changed-targets.outputs.any_oci": str(any_oci).lower(),
        "needs.changed-targets.outputs.vm_guest": str(vm_guest).lower(),
    }
    for name, value in values.items():
        expression = expression.replace(name, repr(value))
    expression = expression.replace("&&", " and ").replace("||", " or ")
    if not re.fullmatch(r"[\w\s'()=!]+", expression):
        raise ValueError(f"Unsupported job condition: {condition}")
    return eval(expression, {"__builtins__": {}}, {})


class MergeQueueTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.workflow = yaml.safe_load(WORKFLOW.read_text())
        cls.jobs = cls.workflow["jobs"]

    def active_jobs(self, event, **kwargs):
        return {name for name, job in self.jobs.items()
                if enabled(job.get("if", "True"), event, **kwargs)}

    def test_queue_runs_only_required_checks(self):
        # PyYAML's YAML 1.1 parser interprets the unquoted `on` key as True.
        self.assertIn("merge_group", self.workflow[True])
        self.assertEqual({"validate", "changed-targets", "pr-builds"},
                         self.active_jobs("merge_group"))

    def test_existing_event_job_selection(self):
        self.assertEqual({"validate", "changed-targets", "pr-build-oci",
                          "pr-guest-contract", "pr-build-vm-guest", "pr-builds"},
                         self.active_jobs("pull_request"))
        self.assertEqual({"validate", "changed-targets", "pr-builds"},
                         self.active_jobs("pull_request", any_oci=False, vm_guest=False))
        for event in ("push", "repository_dispatch", "workflow_dispatch"):
            with self.subTest(event=event):
                self.assertEqual({"matrix", "oci-images", "vm-guest", "summary"},
                                 self.active_jobs(event))
        self.assertEqual(set(), self.active_jobs("unexpected_event"))

    def test_pr_builds_aggregate_dependency_results(self):
        job = self.jobs["pr-builds"]
        step = job["steps"][0]
        expected = {
            "CHANGED_TARGETS": "changed-targets",
            "OCI_BUILD": "pr-build-oci",
            "GUEST_CONTRACT": "pr-guest-contract",
            "VM_BUILD": "pr-build-vm-guest",
        }
        self.assertEqual(set(expected.values()), set(job["needs"]))
        for variable, dependency in expected.items():
            self.assertEqual(f"${{{{ needs.{dependency}.result }}}}", step["env"][variable])
        for bad in (None, *expected):
            for result in (["success", "skipped"] if bad is None else ["failure", "cancelled"]):
                with self.subTest(dependency=bad, result=result):
                    values = dict.fromkeys(expected, "success")
                    if bad is None:
                        values["OCI_BUILD"] = result
                    else:
                        values[bad] = result
                    completed = subprocess.run(
                        ["bash", "-c", step["run"]],
                        env={**os.environ, **values}, capture_output=True,
                    )
                    self.assertEqual(completed.returncode == 0, bad is None)

    def test_both_diff_consumers_use_queue_base(self):
        steps = self.jobs["changed-targets"]["steps"]
        consumers = [step for step in steps if "BASE_SHA" in step.get("env", {})]
        self.assertEqual(2, len(consumers))
        for step in consumers:
            self.assertEqual(
                "${{ github.event.pull_request.base.sha || github.event.merge_group.base_sha }}",
                step["env"]["BASE_SHA"],
            )


if __name__ == "__main__":
    unittest.main()
