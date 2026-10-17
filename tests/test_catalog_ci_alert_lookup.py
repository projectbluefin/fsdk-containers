"""Exercise the alert lookup shell against paginated API fixtures, never GitHub."""

import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

import yaml


ROOT = Path(__file__).resolve().parents[1]
TITLE = "[CI] Build images failed on main"
FAKE_GH = r'''#!/usr/bin/env python3
import json
import os
from pathlib import Path
import sys

args = sys.argv[1:]
fixture = json.loads(Path(os.environ["ALERT_FIXTURE"]).read_text())
with open(os.environ["ALERT_CALLS"], "a") as log:
    log.write(json.dumps(args) + "\n")
if args[0] == "api":
    if "--slurp" in args and ("--jq" in args or "--template" in args):
        raise SystemExit("the --slurp option is not supported with --jq or --template")
    if fixture.get("api_error"):
        if fixture["api_error"] == "partial":
            print(json.dumps([[{"number": 336, "title": "[CI] Build images failed on main", "state": "closed"}]]))
        sys.exit(1)
    endpoint = next(arg for arg in args if arg.startswith("repos/"))
    assert endpoint.startswith("repos/projectbluefin/fsdk-containers/issues?")
    pages = fixture["pages"]
    if "state=all" not in endpoint:
        pages = [[issue for issue in page if issue["state"] == "open"] for page in pages]
    if "--paginate" not in args:
        pages = pages[:1]
    data = pages if "--slurp" in args else pages[0]
    print(json.dumps(data))
    sys.exit(0)
if args[:2] in (["issue", "create"], ["issue", "reopen"], ["issue", "edit"]):
    sys.exit(0)
raise SystemExit("Unexpected gh invocation: " + repr(args))
'''


@unittest.skipIf(shutil.which("jq") is None, "jq is required for API fixture filtering")
class AlertLookupTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.directory = Path(self.temp.name)
        gh = self.directory / "gh"
        gh.write_text(FAKE_GH)
        gh.chmod(0o755)
        self.calls = self.directory / "calls.jsonl"
        self.fixture = self.directory / "fixture.json"
        self.output = self.directory / "output"
        self.steps = yaml.safe_load((ROOT / ".github/workflows/ci-alert.yml").read_text())["jobs"]["alert"]["steps"]
        self.env = {
            **os.environ,
            "PATH": f"{self.directory}:{os.environ['PATH']}",
            "GH_TOKEN": "fixture-only",
            "ALERT_FIXTURE": str(self.fixture),
            "ALERT_CALLS": str(self.calls),
            "GITHUB_OUTPUT": str(self.output),
            "RUN_URL": "https://github.com/projectbluefin/fsdk-containers/actions/runs/123",
            "RUN_ID": "123", "BRANCH": "main", "COMMIT": "a" * 40,
            "FAILURES": "- [build](https://example.invalid/job/1) (failure)",
        }

    def exercise(self, pages, api_error=False):
        self.fixture.write_text(json.dumps({"pages": pages, "api_error": api_error}))
        lookup = next(step for step in self.steps if step.get("id") == "find")
        result = self.run_step(lookup)
        if result.returncode == 0:
            self.env["EXISTING"] = self.output.read_text().removeprefix("issue_number=").strip()
            alert = next(step for step in self.steps if step["name"] == "Create or reopen alert issue")
            result = self.run_step(alert)
        return result, [json.loads(line) for line in self.calls.read_text().splitlines()]

    def run_step(self, step):
        shell = step["run"].replace("${{ github.repository }}", "projectbluefin/fsdk-containers")
        return subprocess.run(["bash", "-c", shell], env=self.env, text=True, capture_output=True)

    def test_closed_alert_beyond_first_hundred_is_reopened_not_duplicated(self):
        newer = [{"number": number, "title": f"Other issue {number}", "state": "open"} for number in range(600, 470, -1)]
        newer[0]["title"] = f"Follow-up: {TITLE}"
        newer[1].update(title=TITLE, pull_request={"url": "https://example.invalid/pr/599"})
        pages = [newer[:100], newer[100:] + [{"number": 336, "title": TITLE, "state": "closed"}]]
        result, calls = self.exercise(pages)
        self.assertEqual(result.returncode, 0, result.stderr)
        mutations = [call for call in calls if call[0] == "issue"]
        self.assertEqual([call[:3] for call in mutations], [["issue", "reopen", "336"], ["issue", "edit", "336"]])
        self.assertIn("--add-label", mutations[1])

    def test_open_exact_alert_is_reused(self):
        result, calls = self.exercise([[{"number": 336, "title": TITLE, "state": "open"}]])
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual([call[:3] for call in calls if call[0] == "issue"], [["issue", "reopen", "336"], ["issue", "edit", "336"]])

    def test_no_exact_issue_creates_alert_without_touching_fuzzy_matches_or_prs(self):
        result, calls = self.exercise([[
            {"number": 600, "title": f"Follow-up: {TITLE}", "state": "open"},
            {"number": 599, "title": TITLE, "state": "open", "pull_request": {}},
        ]])
        self.assertEqual(result.returncode, 0, result.stderr)
        mutations = [call for call in calls if call[0] == "issue"]
        self.assertEqual(len(mutations), 1)
        self.assertEqual(mutations[0][:2], ["issue", "create"])
        self.assertEqual(mutations[0][mutations[0].index("--title") + 1], TITLE)

    def test_successful_empty_lookup_creates_alert(self):
        result, calls = self.exercise([[]])
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual([call[:2] for call in calls if call[0] == "issue"], [["issue", "create"]])

    def test_failed_lookup_never_creates_or_changes_an_issue(self):
        result, calls = self.exercise([[]], api_error=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertFalse(any(call[0] == "issue" for call in calls))
        self.assertFalse(self.output.exists())

    def test_later_page_failure_discards_partial_lookup_output(self):
        result, calls = self.exercise([[]], api_error="partial")
        self.assertNotEqual(result.returncode, 0)
        self.assertFalse(any(call[0] == "issue" for call in calls))
        self.assertFalse(self.output.exists())

    def test_multiple_exact_issues_fail_closed_instead_of_picking_one(self):
        result, calls = self.exercise([[{"number": number, "title": TITLE, "state": "open"} for number in (336, 600)]])
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("Multiple CI alert issues match", result.stderr)
        self.assertFalse(any(call[0] == "issue" for call in calls))
        self.assertFalse(self.output.exists())


if __name__ == "__main__":
    unittest.main()
