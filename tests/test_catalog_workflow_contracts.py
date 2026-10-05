"""Workflow security and publication contract tests.

Validates safety invariants in .github/workflows/ and Justfile:
- printing-runtime-layer.yml: needs.build.result == 'success' requirement,
  same-run immutable index assembly, per-arch signing on all refs,
  compat-auth-file login for cosign, and safe Justfile cleanup.
"""

from pathlib import Path
import re
import unittest
import yaml


ROOT = Path(__file__).parents[1]
WORKFLOW_DIR = ROOT / ".github" / "workflows"
JUSTFILE = ROOT / "Justfile"


class PrintingRuntimeLayerContractTests(unittest.TestCase):
    """Static contracts for printing runtime layer workflow and recipes."""

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

    def test_per_arch_and_index_signing_executes_on_nonmain_refs(self):
        """Cosign signing must not be gated behind REF == main so dev proof images are signed."""
        path = WORKFLOW_DIR / "printing-runtime-layer.yml"
        content = path.read_text()

        # Both the build push step and manifest step should sign without REF == main guard
        self.assertNotIn('if [[ "${REF}" == refs/heads/main ]]; then\n            cosign sign', content,
                         "cosign sign in build step must execute on dev/dispatch runs too")
        self.assertNotIn('if [[ "${REF}" == refs/heads/main ]]; then\n            cosign sign -y "${LAYER_REPO}@${DIGEST}"', content,
                         "cosign sign in manifest step must execute on dev/dispatch runs too")

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
