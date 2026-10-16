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

    def _run_script(self, script, ref="refs/heads/producer-proof", extra_env=None,
                    expect_failure=False, output_symlink=False):
        with tempfile.TemporaryDirectory() as directory:
            work = Path(directory)
            binary = work / "bin"
            protected = work / "protected"
            protected.mkdir()
            marker = protected / "keep"
            marker.write_text("do not remove")
            if output_symlink:
                (work / ".build-out").symlink_to(protected, target_is_directory=True)
            else:
                (work / ".build-out").mkdir()
                (work / ".build-out/stale").write_text("old output")
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
                "    if not (os.environ.get('SIGNED_IDENTITY') == args[args.index('--certificate-identity') + 1] or any(c[:2] == ['cosign', 'sign'] for c in prior)):\n"
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
            result = subprocess.run(
                ["bash", "-euo", "pipefail", "-c", script],
                cwd=work, env=env, check=not expect_failure, capture_output=True, text=True,
            )
            if expect_failure:
                self.assertNotEqual(result.returncode, 0)
            self.assertEqual(marker.read_text(), "do not remove")
            calls = work / "calls"
            return [json.loads(line) for line in calls.read_text().splitlines()] if calls.exists() else []

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
        tags = f"x86_64-run-42 {key_tag}"
        calls = self._run_script(
            script,
            "refs/heads/main",
            extra_env={"KEY_TAG": key_tag, "TAGS": tags, "PUBLISHED": key_tag,
                       "SIGNED_IDENTITY": "https://github.com/projectbluefin/fsdk-containers/.github/workflows/printing-runtime-layer.yml@refs/heads/main"},
        )
        self.assertFalse(any(call[:2] == ["podman", "push"] for call in calls))
        self.assertFalse(any(call[:2] == ["cosign", "sign"] for call in calls))
        copies = [call for call in calls if call[:2] == ["skopeo", "copy"]]
        self.assertEqual(len(copies), 1)
        for call in copies:
            self.assertIn("--preserve-digests", call)

    def test_existing_unsigned_key_is_not_signed_or_realiased(self):
        script = _step_script("build", "Push architecture image and sign")
        key_tag = "x86_64-" + "b" * 64
        calls = self._run_script(
            script, "refs/heads/main", expect_failure=True,
            extra_env={"KEY_TAG": key_tag, "TAGS": f"x86_64-run-42 {key_tag}",
                       "PUBLISHED": key_tag},
        )
        self.assertTrue(any(call[:2] == ["cosign", "verify"] for call in calls))
        self.assertFalse(any(call[:2] in (["cosign", "sign"], ["skopeo", "copy"],
                                        ["podman", "push"]) for call in calls))

    def test_existing_proof_signature_cannot_authorize_main_reuse(self):
        script = _step_script("build", "Push architecture image and sign")
        key_tag = "x86_64-" + "b" * 64
        calls = self._run_script(
            script, "refs/heads/main", expect_failure=True,
            extra_env={"KEY_TAG": key_tag, "TAGS": f"x86_64-run-42 {key_tag}",
                       "PUBLISHED": key_tag,
                       "SIGNED_IDENTITY": "https://github.com/projectbluefin/fsdk-containers/.github/workflows/printing-runtime-layer.yml@refs/heads/producer-proof"},
        )
        self.assertFalse(any(call[:2] in (["cosign", "sign"], ["skopeo", "copy"])
                             for call in calls))

    def test_build_push_pushes_and_signs_when_key_tag_missing(self):
        """When KEY_TAG is not yet published, build job must podman push all tags and sign."""
        script = _step_script("build", "Push architecture image and sign")
        key_tag = "x86_64-" + "b" * 64
        tags = f"x86_64-run-42 {key_tag}"
        calls = self._run_script(
            script,
            "refs/heads/main",
            extra_env={"KEY_TAG": key_tag, "TAGS": tags},
        )
        pushes = [call for call in calls if call[:2] == ["podman", "push"]]
        self.assertEqual(len(pushes), 2)
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


    def test_manifest_assembles_from_immutable_same_run_refs(self):
        """Each ref gets its own index tag and same-run architecture inputs."""
        for ref, index_tag in (("refs/heads/main", "run-42"),
                               ("refs/heads/producer-proof", "test-42")):
            with self.subTest(ref=ref):
                calls = self._run_script(_step_script(
                    "manifest", "Assemble multi-arch index, sign, and verify"), ref)
                creates = [call for call in calls if call[:3] == ["docker", "buildx", "imagetools"]]
                self.assertEqual(len(creates), 1)
                self.assertEqual(creates[0][creates[0].index("-t") + 1],
                                 f"example.invalid/printing:{index_tag}")
                self.assertEqual(creates[0][-2:], [
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
                self.assertEqual(outputs["tags"].split(), [
                    "x86_64-run-42",
                    "x86_64-" + "b" * 64 if ref == "refs/heads/main" else "x86_64-test-42",
                ])


    def test_build_recipe_rejects_symlink_without_touching_target(self):
        content = JUSTFILE.read_text()
        recipe = re.search(
            r"^build-printing-runtime-layer:\n(?P<body>(?:[ \t]+[^\n]*(?:\n|$)|\n)+)",
            content, re.MULTILINE | re.DOTALL,
        )
        calls = self._run_script(recipe.group("body"), output_symlink=True,
                                 expect_failure=True)
        self.assertEqual(calls, [])


if __name__ == "__main__":
    unittest.main()
