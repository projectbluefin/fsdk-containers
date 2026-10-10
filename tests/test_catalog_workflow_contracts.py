"""Workflow security and publication contract tests.

Validates safety invariants in .github/workflows/ and Justfile:
- printing-runtime-layer.yml: needs.build.result == 'success' requirement,
  same-run immutable index assembly, per-arch signing on all refs,
  compat-auth-file login for cosign, and safe Justfile cleanup.
"""

from pathlib import Path
import json
import os
import re
import subprocess
import tempfile
import unittest
import yaml


ROOT = Path(__file__).parents[1]
WORKFLOW_DIR = ROOT / ".github" / "workflows"
JUSTFILE = ROOT / "Justfile"


class PrintingRuntimeLayerContractTests(unittest.TestCase):
    """Contracts for printing runtime layer workflow and recipes."""

    def _run_script(self, script, ref="refs/heads/producer-proof"):
        with tempfile.TemporaryDirectory() as directory:
            work = Path(directory)
            binary = work / "bin"
            binary.mkdir()
            home = work / "home"
            (home / ".docker").mkdir(parents=True)
            (home / ".docker/config.json").write_text('{"auths": {}}')
            stub = binary / "command"
            stub.write_text(
                "#!/usr/bin/env python3\n"
                "import json, os, sys\n"
                "from pathlib import Path\n"
                "name = Path(sys.argv[0]).name\n"
                "args = sys.argv[1:]\n"
                "with open(os.environ['CALLS'], 'a') as stream:\n"
                "    stream.write(json.dumps([name, *args]) + '\\n')\n"
                "if name == 'podman' and args[0] == 'pull':\n"
                "    print('fixture-image')\n"
                "elif name == 'skopeo':\n"
                "    if '--authfile' in args:\n"
                "        json.loads(Path(args[args.index('--authfile') + 1]).read_text())\n"
                "    print(json.dumps({'Digest': 'sha256:' + 'a' * 64}))\n"
            )
            stub.chmod(0o755)
            for command in ("podman", "docker", "cosign", "skopeo", "just"):
                (binary / command).symlink_to(stub)
            env = dict(
                os.environ, PATH=f"{binary}:{os.environ['PATH']}", HOME=str(home),
                CALLS=str(work / "calls"), REF=ref, RUN_ID="42",
                TAGS="x86_64-run-42", LAYER_REPO="example.invalid/printing",
                GITHUB_STEP_SUMMARY=str(work / "summary"),
            )
            script = script.replace("${{ github.actor }}", "fixture-user")
            script = script.replace("${{ secrets.GITHUB_TOKEN }}", "fixture-token")
            subprocess.run(
                ["bash", "-euo", "pipefail", "-c", script],
                cwd=work, env=env, check=True, capture_output=True, text=True,
            )
            return [json.loads(line) for line in (work / "calls").read_text().splitlines()]

    def test_publish_scripts_sign_and_verify_on_main_and_proof_refs(self):
        doc = yaml.safe_load((WORKFLOW_DIR / "printing-runtime-layer.yml").read_text())
        for job, step in (
            ("build", "Push architecture image and sign"),
            ("manifest", "Assemble multi-arch index, sign, and verify"),
        ):
            script = next(s["run"] for s in doc["jobs"][job]["steps"] if s.get("name") == step)
            for ref in ("refs/heads/main", "refs/heads/producer-proof"):
                with self.subTest(job=job, ref=ref):
                    calls = self._run_script(script, ref)
                    self.assertIn(
                        ["cosign", "sign", "-y", "example.invalid/printing@sha256:" + "a" * 64],
                        calls,
                    )
                    self.assertTrue(any(call[:2] == ["cosign", "verify"] for call in calls))

    def test_publish_scripts_keep_credentials_off_skopeo_argv(self):
        doc = yaml.safe_load((WORKFLOW_DIR / "printing-runtime-layer.yml").read_text())
        for job, step in (
            ("build", "Push architecture image and sign"),
            ("manifest", "Assemble multi-arch index, sign, and verify"),
        ):
            script = next(s["run"] for s in doc["jobs"][job]["steps"] if s.get("name") == step)
            with self.subTest(job=job):
                calls = [call for call in self._run_script(script) if call[0] == "skopeo"]
                self.assertTrue(calls)
                for call in calls:
                    self.assertNotIn("--creds", call)
                    self.assertFalse(any("fixture-token" in arg for arg in call))
                    self.assertIn("--authfile", call)

    def test_build_recipe_uses_working_source_cache_options(self):
        content = JUSTFILE.read_text()
        recipe = re.search(
            r"^build-printing-runtime-layer:\n(?P<body>(?:[ \t]+[^\n]*(?:\n|$)|\n)+)",
            content, re.MULTILINE | re.DOTALL,
        )
        self.assertIsNotNone(recipe)
        calls = self._run_script(recipe.group("body"))
        build = next(call for call in calls if call[:2] == ["just", "bst"] and "build" in call)
        self.assertEqual(build, [
            "just", "bst", "--network-retries", "5", "build",
            "--ignore-project-source-remotes",
            "--source-remote", "url=https://cache.projectbluefin.io:11001,push=false",
            "oci/printing-runtime-layer.bst",
        ])

    def test_manifest_job_refuses_failed_builds(self):
        """manifest job must require needs.build.result == 'success'."""
        path = WORKFLOW_DIR / "printing-runtime-layer.yml"
        self.assertTrue(path.exists(), "printing-runtime-layer.yml must exist")
        doc = yaml.safe_load(path.read_text())

        manifest_job = doc["jobs"]["manifest"]
        condition = manifest_job.get("if", "")
        self.assertIn("needs.build.result == 'success'", condition,
                      "manifest job must require needs.build.result == 'success'")

    def test_manifest_assembles_from_immutable_same_run_refs(self):
        """manifest job must assemble index from run-specific tags, not mutable aliases."""
        path = WORKFLOW_DIR / "printing-runtime-layer.yml"
        content = path.read_text()
        self.assertIn("x86_64-run-${RUN_ID}", content,
                      "manifest job must reference immutable x86_64 same-run tag")
        self.assertIn("aarch64-run-${RUN_ID}", content,
                      "manifest job must reference immutable aarch64 same-run tag")

    def test_build_and_manifest_jobs_have_id_token_permission(self):
        """Both jobs must declare id-token: write for Sigstore keyless signing."""
        path = WORKFLOW_DIR / "printing-runtime-layer.yml"
        doc = yaml.safe_load(path.read_text())

        for job_name in ("build", "manifest"):
            perms = doc["jobs"][job_name].get("permissions", {})
            self.assertEqual(perms.get("id-token"), "write",
                             f"Job '{job_name}' must declare id-token: write")

    def test_docker_compat_auth_file_configured_for_cosign(self):
        """Build job must configure ~/.docker/config.json via --compat-auth-file."""
        path = WORKFLOW_DIR / "printing-runtime-layer.yml"
        content = path.read_text()
        self.assertIn("--compat-auth-file ~/.docker/config.json", content,
                      "build login must write ~/.docker/config.json for cosign")

    def test_justfile_build_recipe_refuses_arbitrary_rm(self):
        """build-printing-runtime-layer must not accept an arbitrary DIR to rm -rf."""
        content = JUSTFILE.read_text()
        recipe_match = re.search(r"build-printing-runtime-layer(?P<args>[^:]*):(?P<body>.*?)(?:\n\[|\Z)", content, re.DOTALL)
        self.assertIsNotNone(recipe_match, "build-printing-runtime-layer recipe must exist")

        args = recipe_match.group("args").strip()
        self.assertEqual(args, "", "build-printing-runtime-layer must not accept arbitrary DIR arg")

        body = recipe_match.group("body")
        self.assertIn('.build-out', body, "Recipe must use hardcoded owned scratch directory")
        self.assertIn('-L "${out}"', body, "Recipe must guard against symlinks before removal")


if __name__ == "__main__":
    unittest.main()
