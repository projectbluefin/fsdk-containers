"""Workflow security and publication contract tests.

Validates safety invariants in .github/workflows/ and Justfile:
- printing-runtime-layer.yml: needs.build.result == 'success' requirement,
  same-run immutable index assembly, per-arch signing on all refs (including
  removal-of-signing mutations),
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


def _job(name):
    doc = yaml.safe_load((WORKFLOW_DIR / "printing-runtime-layer.yml").read_text())
    return doc["jobs"][name]


def _step_script(job, step):
    return next(s["run"] for s in _job(job)["steps"] if s.get("name") == step)


class PrintingRuntimeLayerContractTests(unittest.TestCase):
    """Contracts for printing runtime layer workflow and recipes."""

    def _run_script(self, script, ref="refs/heads/producer-proof", extra_env=None):
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
                "log = Path(os.environ['CALLS'])\n"
                "prior = [json.loads(l) for l in log.read_text().splitlines()] if log.exists() else []\n"
                "with open(log, 'a') as stream:\n"
                "    stream.write(json.dumps([name, *args]) + '\\n')\n"
                "def tags():\n"
                "    out = set(os.environ.get('PUBLISHED', '').split())\n"
                "    for c in prior:\n"
                "        if c[:2] == ['podman', 'push'] or c[:2] == ['skopeo', 'copy']:\n"
                "            out.add(c[-1].rsplit(':', 1)[-1])\n"
                "        elif c[:3] == ['docker', 'buildx', 'imagetools']:\n"
                "            out.add(c[c.index('-t') + 1].rsplit(':', 1)[-1])\n"
                "    return out\n"
                "if name == 'podman' and args[0] == 'pull':\n"
                "    print('fixture-image')\n"
                "elif name == 'skopeo' and args[0] == 'inspect':\n"
                "    json.loads(Path(args[args.index('--authfile') + 1]).read_text())\n"
                "    ref = args[-1]\n"
                "    if '@' not in ref and ref.rsplit(':', 1)[-1] not in tags():\n"
                "        sys.exit(1)\n"
                "    print(json.dumps({'Digest': 'sha256:' + 'a' * 64}))\n"
                "elif name == 'cosign' and args[0] == 'verify':\n"
                "    if not (os.environ.get('SIGNED') or any(c[:2] == ['cosign', 'sign'] for c in prior)):\n"
                "        sys.exit(1)\n"
            )
            stub.chmod(0o755)
            for command in ("podman", "docker", "cosign", "skopeo", "just"):
                (binary / command).symlink_to(stub)
            env = dict(
                os.environ, PATH=f"{binary}:{os.environ['PATH']}", HOME=str(home),
                CALLS=str(work / "calls"), REF=ref, RUN_ID="42",
                KEY_TAG="", TAGS="x86_64-run-42", LAYER_REPO="example.invalid/printing",
                SIGNER=f"https://github.com/projectbluefin/fsdk-containers/.github/workflows/printing-runtime-layer.yml@{ref}",
                GITHUB_STEP_SUMMARY=str(work / "summary"),
            )
            if extra_env:
                env.update(extra_env)
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
                    verifies = [call for call in calls if call[:2] == ["cosign", "verify"]]
                    self.assertTrue(verifies)
                    for call in verifies:
                        self.assertIn("--certificate-identity", call)
                        self.assertNotIn("--certificate-identity-regexp", call)

    def test_build_push_reuses_existing_key_tag_without_repushing(self):
        """When KEY_TAG is already published, build job must copy by digest, not podman push."""
        script = _step_script("build", "Push architecture image and sign")
        key_tag = "x86_64-" + "b" * 64
        tags = f"x86_64-run-42 {key_tag} x86_64-latest"
        calls = self._run_script(
            script,
            "refs/heads/main",
            extra_env={"KEY_TAG": key_tag, "TAGS": tags, "PUBLISHED": key_tag, "SIGNED": "1"},
        )
        self.assertFalse(any(call[:2] == ["podman", "push"] for call in calls))
        self.assertFalse(any(call[:2] == ["cosign", "sign"] for call in calls))
        copies = [call for call in calls if call[:2] == ["skopeo", "copy"]]
        self.assertEqual(len(copies), 2)
        for call in copies:
            self.assertIn("--preserve-digests", call)

    def test_build_push_pushes_and_signs_when_key_tag_missing(self):
        """When KEY_TAG is not yet published, build job must podman push all tags and sign."""
        script = _step_script("build", "Push architecture image and sign")
        key_tag = "x86_64-" + "b" * 64
        tags = f"x86_64-run-42 {key_tag} x86_64-latest"
        calls = self._run_script(
            script,
            "refs/heads/main",
            extra_env={"KEY_TAG": key_tag, "TAGS": tags},
        )
        pushes = [call for call in calls if call[:2] == ["podman", "push"]]
        self.assertEqual(len(pushes), 3)
        self.assertTrue(any(call[:2] == ["cosign", "sign"] for call in calls))
    def test_publish_scripts_fail_when_signing_is_removed(self):
        """Dropping `cosign sign` must make verification, and the job, fail."""
        for job, step in (
            ("build", "Push architecture image and sign"),
            ("manifest", "Assemble multi-arch index, sign, and verify"),
        ):
            script = _step_script(job, step)
            mutated = re.sub(r"cosign sign\b[^\n]*", "true", script)
            self.assertNotEqual(mutated, script)
            with self.subTest(job=job):
                with self.assertRaises(subprocess.CalledProcessError) as failure:
                    self._run_script(mutated, "refs/heads/main")
                self.assertNotIn("syntax error", failure.exception.stderr)
                self._run_script(script, "refs/heads/main")

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
        calls = self._run_script(_step_script(
            "manifest", "Assemble multi-arch index, sign, and verify"))
        creates = [call for call in calls if call[:3] == ["docker", "buildx", "imagetools"]]
        self.assertTrue(creates)
        for call in creates:
            self.assertEqual(call[-2:], [
                "example.invalid/printing:x86_64-run-42",
                "example.invalid/printing:aarch64-run-42",
            ])

    def test_build_pushes_same_run_tag_on_main_and_proof_refs(self):
        """build job must publish the <arch>-run-<run_id> tag the manifest consumes."""
        step = next(s for s in _job("build")["steps"] if s.get("id") == "tags")
        for ref in ("refs/heads/main", "refs/heads/producer-proof"):
            with self.subTest(ref=ref), tempfile.TemporaryDirectory() as directory:
                out = Path(directory) / "out"
                out.touch()
                script = step["run"].replace('"$(just printing-runtime-layer-key)"', '"' + "b" * 64 + '"')
                subprocess.run(
                    ["bash", "-euo", "pipefail", "-c", script], check=True, capture_output=True,
                    env=dict(os.environ, REF=ref, RUN_ID="42", ARCH="x86_64", GITHUB_OUTPUT=str(out)),
                )
                outputs = dict(line.split("=", 1) for line in out.read_text().splitlines())
                self.assertEqual(outputs["run_tag"], "x86_64-run-42")
                self.assertIn("x86_64-run-42", outputs["tags"].split())

    def test_build_and_manifest_jobs_have_id_token_permission(self):
        """Both jobs must declare id-token: write for Sigstore keyless signing."""
        path = WORKFLOW_DIR / "printing-runtime-layer.yml"
        doc = yaml.safe_load(path.read_text())

        for job_name in ("build", "manifest"):
            perms = doc["jobs"][job_name].get("permissions", {})
            self.assertEqual(perms.get("id-token"), "write",
                             f"Job '{job_name}' must declare id-token: write")

    def test_docker_compat_auth_file_configured_for_cosign(self):
        """Both publishing jobs must write ~/.docker/config.json via --compat-auth-file."""
        for job_name in ("build", "manifest"):
            with self.subTest(job=job_name):
                login = next(s for s in _job(job_name)["steps"] if s.get("name") == "Log in to ghcr")
                self.assertIn("--compat-auth-file ~/.docker/config.json", login["run"])

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
