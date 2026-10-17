"""Run CI alert workflow shell branches against local API fixtures only."""

import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import tempfile
import unittest

import yaml


ROOT = Path(__file__).resolve().parents[1]
TITLE = "[CI] Build images failed on main"
RUN_URL = "https://github.com/projectbluefin/fsdk-containers/actions/runs/123"
FAKE_GH = r'''#!/usr/bin/env python3
import json
import os
from pathlib import Path
import subprocess
import sys

args = sys.argv[1:]
f = json.loads(Path(os.environ["ALERT_FIXTURE"]).read_text())
with open(os.environ["ALERT_CALLS"], "a") as log:
    log.write(json.dumps(args) + "\n")
if args[0] == "api":
    if "--slurp" in args and ("--jq" in args or "--template" in args):
        raise SystemExit("the --slurp option is not supported with --jq or --template")
    endpoint = next(arg for arg in args if arg.startswith("repos/"))
    if endpoint.endswith("/commits/main"):
        if f.get("commit_error"):
            sys.exit(1)
        data = {"sha": f["main_sha"]}
    elif endpoint.endswith("/actions/runs/123/jobs"):
        if f.get("jobs_error"):
            sys.exit(1)
        data = {"jobs": f["jobs"]}
    elif endpoint.startswith("repos/projectbluefin/fsdk-containers/issues?"):
        data = [f["issues"]] if "--slurp" in args else f["issues"]
    else:
        raise SystemExit("Unexpected API endpoint: " + endpoint)
elif args[:2] == ["issue", "list"]:
    data = f["issues"]
elif args[:2] == ["issue", "view"]:
    if f.get("state_error"):
        sys.exit(1)
    data = {"state": f["issue_state"]}
else:
    assert args[:2] in (["issue", "create"], ["issue", "reopen"], ["issue", "edit"], ["issue", "close"]), args
    sys.exit(0)
if "--jq" not in args:
    print(json.dumps(data))
    sys.exit(0)
result = subprocess.run(["jq", "-r", args[args.index("--jq") + 1]], input=json.dumps(data), text=True, capture_output=True)
sys.stdout.write(result.stdout)
sys.stderr.write(result.stderr)
sys.exit(result.returncode)
'''


@unittest.skipIf(shutil.which("jq") is None, "jq is required for API fixture filtering")
class AlertRecoveryTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.directory = Path(self.temp.name)
        gh = self.directory / "gh"
        gh.write_text(FAKE_GH)
        gh.chmod(0o755)
        self.calls = self.directory / "calls.jsonl"
        self.fixture = self.directory / "fixture.json"
        self.workflow = yaml.safe_load((ROOT / ".github/workflows/ci-alert.yml").read_text())["jobs"]["alert"]
        self.event = {"event": "push", "head_branch": "main", "conclusion": "success", "head_sha": "a" * 40, "html_url": RUN_URL, "id": "123"}
        self.data = {
            "main_sha": "a" * 40, "issue_state": "OPEN",
            "issues": [{"number": 336, "title": TITLE, "state": "open"}],
            "jobs": [{"name": conclusion + " job", "html_url": f"https://example.invalid/jobs/{index}", "conclusion": conclusion}
                     for index, conclusion in enumerate(("failure", "cancelled", "timed_out", "skipped", "success"))],
        }
        self.outputs = {}

    def resolve(self, expression):
        if expression == "github.repository":
            return "projectbluefin/fsdk-containers"
        if expression == "secrets.GITHUB_TOKEN":
            return "fixture-only"
        if expression.startswith("github.event.workflow_run."):
            return self.event.get(expression.rsplit(".", 1)[1], "")
        match = re.fullmatch(r"steps\.(\w+)\.outputs\.(\w+)", expression)
        if match:
            return self.outputs.get(match[1], {}).get(match[2], "")
        raise AssertionError("Unknown workflow expression: " + expression)

    def render(self, text):
        return re.sub(r"\$\{\{\s*(.*?)\s*\}\}", lambda match: self.resolve(match[1]), text)

    def enabled(self, condition):
        condition = re.sub(r"github\.event\.workflow_run\.\w+|steps\.\w+\.outputs\.\w+", lambda match: repr(self.resolve(match[0])), condition)
        return eval(condition.replace("&&", " and ").replace("||", " or "), {"__builtins__": {}})

    def exercise(self):
        self.fixture.write_text(json.dumps(self.data))
        if not self.enabled(self.workflow["if"]):
            return 0, []
        for index, step in enumerate(self.workflow["steps"]):
            if not self.enabled(step.get("if", "True")):
                continue
            output = self.directory / f"output-{index}"
            env = {
                **os.environ,
                "PATH": f"{self.directory}:{os.environ['PATH']}",
                "ALERT_FIXTURE": str(self.fixture), "ALERT_CALLS": str(self.calls),
                "GITHUB_OUTPUT": str(output),
                **{key: self.render(value) for key, value in step.get("env", {}).items()},
            }
            result = subprocess.run(["bash", "-c", self.render(step["run"])], env=env, text=True, capture_output=True)
            if result.returncode:
                break
            if step.get("id") and output.exists():
                values = {}
                lines = iter(output.read_text().splitlines())
                for line in lines:
                    if "<<" in line:
                        key, delimiter = line.split("<<", 1)
                        body = []
                        for line in lines:
                            if line == delimiter:
                                break
                            body.append(line)
                        values[key] = "\n".join(body)
                    else:
                        key, value = line.split("=", 1)
                        values[key] = value
                self.outputs[step["id"]] = values
        calls = [json.loads(line) for line in self.calls.read_text().splitlines()] if self.calls.exists() else []
        return result.returncode, calls

    def test_current_green_closes_open_alert_with_actual_run_link(self):
        code, calls = self.exercise()
        self.assertEqual(code, 0)
        closes = [call for call in calls if call[:2] == ["issue", "close"]]
        self.assertEqual(len(closes), 1)
        self.assertEqual(closes[0][2], "336")
        self.assertEqual(closes[0][-1], f"Build images is green on main again: {RUN_URL}")

    def test_repeated_green_does_not_comment_again(self):
        self.data["issue_state"] = "CLOSED"
        code, calls = self.exercise()
        self.assertEqual(code, 0)
        self.assertFalse(any(call[:2] == ["issue", "close"] for call in calls))

    def test_stale_green_never_closes_newer_alert(self):
        self.data["main_sha"] = "b" * 40
        code, calls = self.exercise()
        self.assertEqual(code, 0)
        self.assertFalse(any(call[:2] in (["issue", "view"], ["issue", "close"]) for call in calls))

    def test_failed_main_lookup_does_not_close_alert(self):
        self.data["commit_error"] = True
        code, calls = self.exercise()
        self.assertNotEqual(code, 0)
        self.assertFalse(any(call[:2] == ["issue", "close"] for call in calls))

    def test_failed_state_lookup_does_not_close_alert(self):
        self.data["state_error"] = True
        code, calls = self.exercise()
        self.assertNotEqual(code, 0)
        self.assertFalse(any(call[:2] == ["issue", "close"] for call in calls))

    def test_failure_reopens_alert_and_reports_root_cause_jobs(self):
        self.event["conclusion"] = "failure"
        self.data["issue_state"] = "CLOSED"
        code, calls = self.exercise()
        self.assertEqual(code, 0)
        self.assertEqual([call[:3] for call in calls if call[:2] == ["issue", "reopen"]], [["issue", "reopen", "336"]])
        edit = next(call for call in calls if call[:2] == ["issue", "edit"])
        body = edit[edit.index("--body") + 1]
        for conclusion in ("failure", "cancelled", "timed_out", "skipped"):
            self.assertIn(f"({conclusion})", body)
        self.assertNotIn("(success)", body)
        self.assertIn(RUN_URL, body)
        self.assertFalse(any(call[:2] in (["issue", "create"], ["issue", "close"]) for call in calls))

    def test_failure_creates_alert_only_when_no_existing_issue(self):
        self.event["conclusion"] = "failure"
        self.data["issues"] = []
        code, calls = self.exercise()
        self.assertEqual(code, 0)
        self.assertEqual(len([call for call in calls if call[:2] == ["issue", "create"]]), 1)
        self.assertFalse(any(call[:2] == ["issue", "close"] for call in calls))

    def test_success_without_alert_does_not_create_one(self):
        self.data["issues"] = []
        code, calls = self.exercise()
        self.assertEqual(code, 0)
        self.assertFalse(any(call[:2] in (["issue", "create"], ["issue", "close"]) for call in calls))

    def test_failed_jobs_lookup_stops_before_issue_mutation(self):
        self.event["conclusion"] = "failure"
        self.data["jobs_error"] = True
        code, calls = self.exercise()
        self.assertNotEqual(code, 0)
        self.assertFalse(any(call[0] == "issue" for call in calls))

    def test_unrelated_runs_are_ignored(self):
        for key, value in (("event", "pull_request"), ("head_branch", "other"), ("conclusion", "cancelled")):
            with self.subTest(key=key):
                original = self.event[key]
                self.event[key] = value
                code, calls = self.exercise()
                self.assertEqual((code, calls), (0, []))
                self.event[key] = original


if __name__ == "__main__":
    unittest.main()
