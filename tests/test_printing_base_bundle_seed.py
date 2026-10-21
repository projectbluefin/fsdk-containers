"""The shared printing-base seed step accepts only the bundle's real signer.

.github/actions/seed-printing-base is how printer applications satisfy rule 4
of the consumer contract (docs/skills/printing-base.md): unpack the
printing-base-devel bundle into the BuildStream cache only after cosign
accepts the digest, and never fail the job. The bundle's only signer is
printing-base.yml on main, so the action, the documented commands and that
workflow must name the same identity; an identity regexp would also accept
other workflows and branches of this repository.

seed.sh runs here against stub `just`, `skopeo`, `cosign`, `jq` and `tar`
that record their arguments, so every exit path runs on the host without a
registry or BuildStream.
"""

from pathlib import Path
import os
import re
import stat
import subprocess
import tempfile
import unittest

import yaml

ROOT = Path(__file__).parents[1]
ACTION_DIR = ROOT / ".github" / "actions" / "seed-printing-base"
ACTION = ACTION_DIR / "action.yml"
SEED = ACTION_DIR / "seed.sh"
DOC = ROOT / "docs" / "skills" / "printing-base.md"
PUBLISHER = ROOT / ".github" / "workflows" / "printing-base.yml"

SIGNER = (
    "https://github.com/projectbluefin/fsdk-containers/"
    ".github/workflows/printing-base.yml@refs/heads/main"
)
KEY = "a" * 64
DIGEST = "sha256:" + "d" * 64

STUBS = {
    "just": """#!/usr/bin/env bash
echo "just $*" >> "$CALLS"
case "$*" in
  *%{full-key}*) printf '%s\\n' "$STUB_KEY" ;;
  *%{state}*) cat "$STATE_FILE" ;;
esac
""",
    "skopeo": """#!/usr/bin/env bash
echo "skopeo $*" >> "$CALLS"
if [[ "$1" == inspect ]]; then printf '%s\\n' "$STUB_DIGEST"; fi
if [[ "$1" == copy ]]; then
  dir="${3#dir:}"
  printf '{"layers":[{"digest":"sha256:layer"}]}' > "$dir/manifest.json"
fi
""",
    "cosign": """#!/usr/bin/env bash
echo "cosign $*" >> "$CALLS"
exit "${COSIGN_RC:-0}"
""",
    "jq": """#!/usr/bin/env bash
echo "jq $*" >> "$CALLS"
echo "sha256:layer"
""",
    "tar": """#!/usr/bin/env bash
echo "tar $*" >> "$CALLS"
echo cached > "$STATE_FILE"
""",
}


class SignerIdentity(unittest.TestCase):
    def test_publisher_signs_only_from_main(self):
        workflow = yaml.safe_load(PUBLISHER.read_text())
        # PyYAML reads the bare `on:` key as boolean True.
        triggers = workflow.get("on", workflow.get(True))
        self.assertEqual(triggers["push"]["branches"], ["main"])
        self.assertIn('cosign sign -y "${BUNDLE_REPO}@${DIGEST}"', PUBLISHER.read_text())

    def test_seed_script_names_the_exact_signer(self):
        text = SEED.read_text()
        self.assertIn(f"--certificate-identity '{SIGNER}'", text)
        self.assertNotIn("--certificate-identity-regexp", text)

    def test_contract_rule_names_the_exact_signer_and_the_action(self):
        rule = DOC.read_text().split("\n4. Seed the cache", 1)[1].split("\n5. ", 1)[0]
        self.assertIn(f"--certificate-identity '{SIGNER}'", rule)
        self.assertNotIn("--certificate-identity-regexp", rule)
        self.assertIn(
            "projectbluefin/fsdk-containers/.github/actions/seed-printing-base@", rule
        )


class ActionShape(unittest.TestCase):
    def setUp(self):
        self.action = yaml.safe_load(ACTION.read_text())

    def test_arch_is_the_only_required_input(self):
        self.assertEqual(
            {k: v.get("required") for k, v in self.action["inputs"].items()},
            {"arch": True},
        )

    def test_runs_the_shipped_script_and_never_fails_on_cosign_install(self):
        runs = self.action["runs"]
        self.assertEqual(runs["using"], "composite")
        install, seed = runs["steps"]
        self.assertRegex(install["uses"], r"^sigstore/cosign-installer@[0-9a-f]{40}$")
        self.assertTrue(install["continue-on-error"])
        self.assertEqual(seed["env"]["ARCH"], "${{ inputs.arch }}")
        self.assertEqual(seed["run"], 'bash "${GITHUB_ACTION_PATH}/seed.sh"')


class SeedScript(unittest.TestCase):
    def run_seed(self, key=KEY, state="", cosign_rc=0):
        tmp = Path(self.tmp.name)
        state_file = tmp / "state"
        state_file.write_text(state + "\n")
        calls = tmp / "calls"
        calls.write_text("")
        env = dict(
            os.environ,
            PATH=f"{self.bin}:{os.environ['PATH']}",
            HOME=str(tmp / "home"),
            ARCH="x86_64",
            CALLS=str(calls),
            STATE_FILE=str(state_file),
            STUB_KEY=key,
            STUB_DIGEST=DIGEST,
            COSIGN_RC=str(cosign_rc),
        )
        result = subprocess.run(
            ["bash", str(SEED)], env=env, capture_output=True, text=True, check=False
        )
        return result, calls.read_text().splitlines()

    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.bin = Path(self.tmp.name) / "bin"
        self.bin.mkdir()
        for name, body in STUBS.items():
            path = self.bin / name
            path.write_text(body)
            path.chmod(path.stat().st_mode | stat.S_IXUSR)

    def tools(self, calls):
        return [c.split()[0] for c in calls]

    def test_requires_arch(self):
        env = {k: v for k, v in os.environ.items() if k != "ARCH"}
        result = subprocess.run(["bash", str(SEED)], env=env, capture_output=True, text=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("ARCH must name", result.stderr)

    def test_unreadable_key_builds_locally(self):
        result, calls = self.run_seed(key="not-a-key")
        self.assertEqual(result.returncode, 0)
        self.assertIn("cannot compute the x86_64 key", result.stdout)
        self.assertEqual(set(self.tools(calls)), {"just"})

    def test_already_cached_skips_the_registry(self):
        result, calls = self.run_seed(state="cached")
        self.assertEqual(result.returncode, 0)
        self.assertIn("is already cached", result.stdout)
        self.assertEqual(set(self.tools(calls)), {"just"})

    def test_rejected_signature_never_copies_or_extracts(self):
        result, calls = self.run_seed(cosign_rc=1)
        self.assertEqual(result.returncode, 0)
        self.assertIn(f"seeding x86_64-{KEY} failed; building it locally", result.stdout)
        self.assertNotIn("tar", self.tools(calls))
        self.assertFalse(any(c.startswith("skopeo copy") for c in calls))

    def test_verified_digest_is_the_one_copied_and_extracted(self):
        result, calls = self.run_seed()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn(f"printing base seeded from x86_64-{KEY}", result.stdout)
        repo = "ghcr.io/projectbluefin/printing-base-devel"
        self.assertIn(
            f"skopeo inspect --format {{{{.Digest}}}} docker://{repo}:x86_64-{KEY}", calls
        )
        (verify,) = [c for c in calls if c.startswith("cosign ")]
        self.assertEqual(
            verify,
            f"cosign verify --certificate-identity {SIGNER} "
            f"--certificate-oidc-issuer https://token.actions.githubusercontent.com "
            f"{repo}@{DIGEST}",
        )
        (copy,) = [c for c in calls if c.startswith("skopeo copy")]
        self.assertTrue(copy.startswith(f"skopeo copy docker://{repo}@{DIGEST} dir:"))
        tools = self.tools(calls)
        self.assertLess(tools.index("cosign"), tools.index("tar"))
        (extract,) = [c for c in calls if c.startswith("tar ")]
        self.assertRegex(
            extract, rf"^tar -C {re.escape(self.tmp.name)}/home/\.cache/buildstream -xf .+/layer$"
        )

    def test_unpacked_but_still_uncached_warns(self):
        (self.bin / "tar").write_text('#!/usr/bin/env bash\necho "tar $*" >> "$CALLS"\n')
        result, _ = self.run_seed()
        self.assertEqual(result.returncode, 0)
        self.assertIn("not verified or not cached after seeding", result.stdout)


if __name__ == "__main__":
    unittest.main()
