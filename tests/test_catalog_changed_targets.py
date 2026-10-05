"""Executable coverage for the `changed-targets` recipe in the Justfile.

`just changed-targets BASE HEAD` is the pull-request build gate: `build.yml`
feeds its JSON straight into the `oci_images` matrix and the `vm_guest`
condition. Until now nothing executed it. `tests/test_catalog_conformance.py`
asserts things *about* `elements/targets.json` and re-implements the recipe's
prefix/exact matching in Python (`PathOwnershipTests._owns`) — a mirror, which
by construction cannot catch the recipe diverging from it. A gate that selects
too few targets fails open: the affected image is simply not built, and the PR
goes green without ever having been tested.

These tests run the recipe's real shell body against synthetic git
repositories, so the assertions are about the bash that CI actually executes.

The body is lifted out of the Justfile at test time rather than being copied
here, for the same reason: a copy is a second implementation. `just` is not a
dependency of this suite (the Python test lanes do not install it); only
`bash`, `git` and `jq` are, all of which the recipe itself already requires.
"""

import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).parents[1]
JUSTFILE = ROOT / "Justfile"

RECIPE = "changed-targets"

# A manifest with the same *shape* as elements/targets.json but fixed content,
# so these tests describe the recipe's behaviour and do not fail every time an
# image is added to the real manifest.
MANIFEST = {
    "oci_images": ["alpha", "bravo", "charlie"],
    "canary_image": "alpha",
    "shared_paths": ["project.conf", "include/"],
    "vm_guest_paths": ["elements/podman-vm/", "tests/vm-boot.sh"],
    "image_paths": {
        "alpha": ["elements/oci/alpha.bst", "catalog/alpha.yaml"],
        "bravo": ["elements/oci/bravo.bst", "elements/bravo/"],
        "charlie": ["elements/oci/charlie.bst"],
    },
}


def extract_recipe_body(text, name):
    """Return the shell body of `name` from a Justfile, as a runnable script.

    Raises AssertionError rather than returning something plausible-but-wrong:
    a silently empty body would make every test below pass vacuously.
    """
    lines = text.splitlines()
    start = None
    for i, line in enumerate(lines):
        if re.match(rf"^{re.escape(name)}(\s|:)", line) and line.rstrip().endswith(":"):
            start = i + 1
            break
    if start is None:
        raise AssertionError(
            f"recipe {name!r} not found in the Justfile — it was renamed or "
            f"removed, and this test no longer covers the build gate"
        )

    body = []
    for line in lines[start:]:
        if line.strip() == "":
            body.append("")
            continue
        if not line.startswith((" ", "\t")):
            break
        body.append(line[4:] if line.startswith("    ") else line.lstrip())

    if body and body[0].startswith("#!"):
        body = body[1:]

    script = "\n".join(body).strip("\n")
    if not script:
        raise AssertionError(f"recipe {name!r} has an empty body")

    script = script.replace("{{BASE}}", "${1}").replace("{{HEAD}}", "${2}")
    leftover = re.findall(r"\{\{.*?\}\}", script)
    if leftover:
        raise AssertionError(
            f"recipe {name!r} gained unsubstituted just interpolations "
            f"{leftover} — this harness must learn them before it can claim "
            f"to cover the recipe"
        )
    return "#!/usr/bin/env bash\n" + script + "\n"


RECIPE_BODY = extract_recipe_body(JUSTFILE.read_text(), RECIPE)


# Host-global git config leaks into the temp repo and into the gate script's
# `git diff`/`git merge-base` if the child inherits the parent's environment
# verbatim: `core.hooksPath` (the focus of #370), but also `diff.renames`,
# `commit.template`, `core.autocrlf`, `core.attributes`, alias.*, etc. The
# recipe's behaviour must not depend on what the developer happens to have set
# in ~/.gitconfig. GIT_CONFIG_GLOBAL=/dev/null disables ~/.gitconfig and
# GIT_CONFIG_NOSYSTEM=1 disables /etc/gitconfig; the test still sets user.email
# and user.name on the temp repo's local config, which is independent of
# GIT_CONFIG_GLOBAL.
HERMETIC_GIT_ENV = {
    **os.environ,
    "GIT_CONFIG_GLOBAL": "/dev/null",
    "GIT_CONFIG_NOSYSTEM": "1",
}


def git(repo, *args):
    return subprocess.run(
        ["git", *args],
        cwd=repo,
        check=True,
        capture_output=True,
        text=True,
        env=HERMETIC_GIT_ENV,
    ).stdout


@unittest.skipIf(shutil.which("jq") is None, "jq is required by the recipe")
class ChangedTargetsTests(unittest.TestCase):
    """Behaviour of the pull-request build gate, exercised as shell."""

    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.repo = Path(self.tmp.name)
        self.addCleanup(self.tmp.cleanup)

        self.script = self.repo / "changed-targets.sh"
        self.script.write_text(RECIPE_BODY)
        self.script.chmod(0o755)

        git(self.repo, "init", "-q", "-b", "main")
        git(self.repo, "config", "user.email", "quality@example.invalid")
        git(self.repo, "config", "user.name", "quality")
        git(self.repo, "config", "commit.gpgsign", "false")
        git(self.repo, "config", "core.hooksPath", "/dev/null")

        self.write("elements/targets.json", json.dumps(MANIFEST, indent=2))
        self.write("README.md", "seed\n")
        self.commit("base")
        self.base = git(self.repo, "rev-parse", "HEAD").strip()

    def write(self, relpath, content=None):
        # Content is unique per path: identical blobs make `git diff` report a
        # rename (destination only) instead of an add and a delete, which
        # would hide half of a change set from the gate under test.
        path = self.repo / relpath
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(content if content is not None else f"{relpath}\n")

    def commit(self, message):
        git(self.repo, "add", "-A")
        git(self.repo, "commit", "-q", "--no-verify", "-m", message)

    def run_gate(self, base=None, head="HEAD"):
        proc = subprocess.run(
            [str(self.script), base or self.base, head],
            cwd=self.repo,
            capture_output=True,
            text=True,
            env=HERMETIC_GIT_ENV,
        )
        self.assertEqual(
            proc.returncode,
            0,
            f"recipe exited {proc.returncode}\nstdout: {proc.stdout}\n"
            f"stderr: {proc.stderr}",
        )
        return json.loads(proc.stdout)

    # -- shape -------------------------------------------------------------

    def test_output_is_exactly_the_two_keys_build_yml_reads(self):
        """build.yml reads .oci_images and .vm_guest; nothing else is a
        contract, and a missing key makes fromJson() fail mid-workflow."""
        self.write("docs/notes.md")
        self.commit("docs")
        result = self.run_gate()
        self.assertEqual(sorted(result), ["oci_images", "vm_guest"])
        self.assertIsInstance(result["oci_images"], list)
        self.assertIsInstance(result["vm_guest"], bool)

    def test_output_is_a_single_line_of_json(self):
        """The workflow captures it in a shell variable and echoes it into
        $GITHUB_OUTPUT, which is line-oriented."""
        proc = subprocess.run(
            [str(self.script), self.base, "HEAD"],
            cwd=self.repo,
            capture_output=True,
            text=True,
            check=True,
            env=HERMETIC_GIT_ENV,
        )
        self.assertEqual(len(proc.stdout.strip().splitlines()), 1)

    # -- selection ---------------------------------------------------------

    def test_no_changes_selects_nothing(self):
        result = self.run_gate()
        self.assertEqual(result, {"oci_images": [], "vm_guest": False})

    def test_unowned_file_selects_nothing(self):
        """A file no image claims must not build anything — but it also must
        not error out under `set -euo pipefail` on the empty array."""
        self.write("README.md", "changed\n")
        self.commit("readme")
        self.assertEqual(self.run_gate(), {"oci_images": [], "vm_guest": False})

    def test_owned_file_selects_only_its_image(self):
        self.write("elements/oci/bravo.bst")
        self.commit("bravo")
        result = self.run_gate()
        self.assertEqual(result["oci_images"], ["bravo"])
        self.assertFalse(result["vm_guest"])

    def test_trailing_slash_prefix_matches_nested_paths(self):
        self.write("elements/bravo/files/deep/thing.conf")
        self.commit("nested")
        self.assertEqual(self.run_gate()["oci_images"], ["bravo"])

    def test_exact_path_does_not_match_a_longer_sibling(self):
        """The documented reason the matcher is not a plain prefix test:
        `elements/oci/alpha.bst` must never match `alpha-extra.bst`."""
        self.write("elements/oci/alpha-extra.bst")
        self.commit("sibling")
        self.assertEqual(self.run_gate()["oci_images"], [])

    def test_a_directory_named_like_an_exact_path_does_not_match(self):
        self.write("elements/oci/alpha.bst.d/extra.conf")
        self.commit("lookalike dir")
        self.assertEqual(self.run_gate()["oci_images"], [])

    def test_second_owned_path_selects_the_same_image(self):
        self.write("catalog/alpha.yaml")
        self.commit("alpha record")
        self.assertEqual(self.run_gate()["oci_images"], ["alpha"])

    def test_several_images_are_selected_together(self):
        self.write("elements/oci/bravo.bst")
        self.write("elements/oci/charlie.bst")
        self.commit("two images")
        self.assertEqual(self.run_gate()["oci_images"], ["bravo", "charlie"])

    def test_selection_is_in_manifest_order_not_change_order(self):
        """The matrix must be stable: the same change set always yields the
        same matrix, regardless of the order git happens to list files."""
        self.write("elements/oci/charlie.bst")
        self.write("elements/oci/alpha.bst")
        self.write("elements/oci/bravo.bst")
        self.commit("all three")
        self.assertEqual(
            self.run_gate()["oci_images"],
            MANIFEST["oci_images"],
        )

    def test_one_image_touched_twice_appears_once(self):
        self.write("elements/oci/bravo.bst")
        self.write("elements/bravo/extra.conf")
        self.commit("bravo twice")
        self.assertEqual(self.run_gate()["oci_images"], ["bravo"])

    def test_a_deleted_owned_file_still_selects_its_image(self):
        """Deleting an element is exactly the kind of change that must be
        built, and `git diff --name-only` reports deletions."""
        self.write("elements/oci/charlie.bst")
        self.commit("add charlie")
        base = git(self.repo, "rev-parse", "HEAD").strip()
        (self.repo / "elements/oci/charlie.bst").unlink()
        self.commit("delete charlie")
        self.assertEqual(self.run_gate(base=base)["oci_images"], ["charlie"])

    def test_paths_with_spaces_are_handled(self):
        self.write("elements/bravo/a file.conf")
        self.commit("spaces")
        self.assertEqual(self.run_gate()["oci_images"], ["bravo"])

    # -- shared paths and the canary --------------------------------------

    def test_shared_file_selects_the_canary(self):
        self.write("project.conf", "changed\n")
        self.commit("shared")
        self.assertEqual(
            self.run_gate()["oci_images"], [MANIFEST["canary_image"]]
        )

    def test_shared_prefix_selects_the_canary(self):
        self.write("include/fragment.yml")
        self.commit("shared prefix")
        self.assertEqual(
            self.run_gate()["oci_images"], [MANIFEST["canary_image"]]
        )

    def test_shared_plus_the_canary_itself_yields_one_entry(self):
        """`alpha` is both the canary and an owner; it must not be listed
        twice or the matrix runs the same build twice."""
        self.write("project.conf", "changed\n")
        self.write("elements/oci/alpha.bst")
        self.commit("shared and alpha")
        self.assertEqual(self.run_gate()["oci_images"], ["alpha"])

    def test_shared_plus_another_image_keeps_manifest_order(self):
        self.write("project.conf", "changed\n")
        self.write("elements/oci/charlie.bst")
        self.commit("shared and charlie")
        self.assertEqual(self.run_gate()["oci_images"], ["alpha", "charlie"])

    # -- vm_guest ----------------------------------------------------------

    def test_vm_guest_path_sets_the_flag(self):
        self.write("elements/podman-vm/podman-vm.bst")
        self.commit("vm element")
        result = self.run_gate()
        self.assertTrue(result["vm_guest"])

    def test_vm_guest_exact_path_sets_the_flag(self):
        self.write("tests/vm-boot.sh")
        self.commit("vm boot script")
        self.assertTrue(self.run_gate()["vm_guest"])

    def test_vm_guest_path_alone_selects_no_oci_image(self):
        """The guest lane is a separate, expensive job: touching it must not
        drag seven OCI builds along with it."""
        self.write("elements/podman-vm/podman-vm.bst")
        self.commit("vm only")
        self.assertEqual(self.run_gate()["oci_images"], [])

    def test_vm_guest_is_false_for_an_unrelated_change(self):
        self.write("elements/oci/bravo.bst")
        self.commit("bravo")
        self.assertFalse(self.run_gate()["vm_guest"])

    def test_vm_guest_and_oci_can_both_be_selected(self):
        self.write("elements/podman-vm/podman-vm.bst")
        self.write("elements/oci/bravo.bst")
        self.commit("both lanes")
        result = self.run_gate()
        self.assertEqual(result["oci_images"], ["bravo"])
        self.assertTrue(result["vm_guest"])

    # -- merge-base semantics ---------------------------------------------

    def test_a_pr_is_judged_on_its_own_commits_only(self):
        """The recipe diffs from the merge base, so commits that landed on the
        base branch after the branch forked must not enter the matrix."""
        git(self.repo, "checkout", "-q", "-b", "feature")
        self.write("elements/oci/bravo.bst")
        self.commit("feature: bravo")

        git(self.repo, "checkout", "-q", "main")
        self.write("elements/oci/charlie.bst")
        self.commit("main: charlie moved on")

        git(self.repo, "checkout", "-q", "feature")
        self.assertEqual(
            self.run_gate(base="main", head="feature")["oci_images"],
            ["bravo"],
        )

    def test_all_commits_on_the_branch_are_considered(self):
        git(self.repo, "checkout", "-q", "-b", "feature")
        self.write("elements/oci/bravo.bst")
        self.commit("first")
        self.write("elements/oci/charlie.bst")
        self.commit("second")
        self.assertEqual(
            self.run_gate(base="main", head="feature")["oci_images"],
            ["bravo", "charlie"],
        )


class RecipeIsStillTheOneCiRunsTests(unittest.TestCase):
    """Guards this harness itself: if the recipe moves, these tests would keep
    passing against a stale copy unless something asserts on the source."""

    def test_the_recipe_exists_and_declares_base_and_head(self):
        declaration = re.search(
            rf"^{RECIPE} BASE HEAD=.*:$",
            JUSTFILE.read_text(),
            re.MULTILINE,
        )
        self.assertIsNotNone(
            declaration,
            "`changed-targets BASE HEAD=...` was renamed or its signature "
            "changed; build.yml's call and this harness both assume it",
        )

    def test_the_extracted_body_is_the_gate_and_not_a_fragment(self):
        for needle in ("MERGE_BASE", "matches_any", "canary_image", "vm_guest"):
            self.assertIn(needle, RECIPE_BODY, f"extracted body lost {needle}")

    def test_the_real_manifest_has_the_keys_the_recipe_reads(self):
        real = json.loads((ROOT / "elements" / "targets.json").read_text())
        for key in ("oci_images", "canary_image", "shared_paths",
                    "vm_guest_paths", "image_paths"):
            self.assertIn(key, real, f"elements/targets.json lost {key}")
        self.assertIn(
            real["canary_image"],
            real["oci_images"],
            "canary_image is not a published image, so a shared-path change "
            "would select a target the build matrix cannot build",
        )


class GitEnvIsHermeticTests(unittest.TestCase):
    """The temp repo and the gate script must not see the developer's
    ~/.gitconfig: a host-global `core.hooksPath`, `diff.renames`,
    `commit.template`, etc. would otherwise let the suite's behaviour drift
    with the developer's shell. PR #370 added hooks isolation; #375 extends
    that to the full git config surface by passing GIT_CONFIG_GLOBAL and
    GIT_CONFIG_NOSYSTEM to every child process.

    This test pins the contract at the source of truth: HERMETIC_GIT_ENV
    must explicitly carry both overrides. If a future refactor reverts the
    dict to `os.environ.copy()` (no overrides), the developer's ~/.gitconfig
    leaks into every child and the suite silently drifts with their shell.
    """

    def test_hermetic_env_overrides_host_and_system_gitconfig(self):
        self.assertEqual(
            HERMETIC_GIT_ENV.get("GIT_CONFIG_GLOBAL"), "/dev/null",
            "HERMETIC_GIT_ENV does not override GIT_CONFIG_GLOBAL — the "
            "parent's ~/.gitconfig will leak into every child git process",
        )
        self.assertEqual(
            HERMETIC_GIT_ENV.get("GIT_CONFIG_NOSYSTEM"), "1",
            "HERMETIC_GIT_ENV does not set GIT_CONFIG_NOSYSTEM=1 — the "
            "system /etc/gitconfig will leak into every child git process",
        )

    def test_helper_strips_host_config(self):
        """End-to-end: a hostile GIT_CONFIG_GLOBAL that the parent process
        carries does not propagate into a child git invocation made through
        the `git()` helper. Pins the contract that the helper's
        env=HERMETIC_GIT_ENV argument wins over the inherited environment.

        Setup writes a real gitconfig file with hostile values and points
        GIT_CONFIG_GLOBAL at it via os.environ (the parent). A bare git
        invocation under the helper's path must NOT see the hostile values;
        the same invocation against the parent's env (the regression path)
        must see them, so the negative assertion below is meaningful."""
        with tempfile.TemporaryDirectory() as tmp:
            host_cfg = Path(tmp) / "host.gitconfig"
            host_cfg.write_text(
                "[diff]\n\t renames = false\n"
                "[commit]\n\ttemplate = /nonexistent/template\n"
            )
            repo = Path(tmp) / "repo"
            repo.mkdir()
            saved_global = os.environ.get("GIT_CONFIG_GLOBAL")
            saved_nosystem = os.environ.get("GIT_CONFIG_NOSYSTEM")
            os.environ["GIT_CONFIG_GLOBAL"] = str(host_cfg)
            os.environ["GIT_CONFIG_NOSYSTEM"] = "0"
            try:
                # Init under HERMETIC_GIT_ENV so setUp doesn't leak.
                git(repo, "init", "-q", "-b", "main")
                git(repo, "config", "user.email", "quality@example.invalid")
                git(repo, "config", "user.name", "quality")

                # Regression path: a child that inherits os.environ would
                # see diff.renames = false. Confirm the host stand-in is
                # actually wired up so the negative assertion below is
                # meaningful.
                leaked = subprocess.run(
                    ["git", "config", "--get", "diff.renames"],
                    cwd=repo, capture_output=True, text=True,
                )
                self.assertEqual(
                    leaked.returncode, 0,
                    "test wiring broken: host stand-in did not propagate "
                    "diff.renames via os.environ; the negative assertion "
                    "below would be vacuous",
                )
                self.assertEqual(leaked.stdout.strip(), "false")

                # Production path: the git() helper must pass
                # env=HERMETIC_GIT_ENV (with GIT_CONFIG_GLOBAL=/dev/null),
                # hiding the host stand-in. Probe via the helper itself —
                # this is what the regression actually exercises: a refactor
                # that drops env=HERMETIC_GIT_ENV from subprocess.run
                # inside git() would let the host stand-in through. The
                # helper raises CalledProcessError on non-zero exit, so a
                # visible diff.renames = false would make the helper exit 0
                # and not raise.
                from tests.test_catalog_changed_targets import git as helper_git
                with self.assertRaises(
                    subprocess.CalledProcessError,
                    msg="git() helper returned 0 — diff.renames was visible "
                        "to the child, so the helper is no longer overriding "
                        "GIT_CONFIG_GLOBAL via HERMETIC_GIT_ENV",
                ):
                    helper_git(repo, "config", "--get", "diff.renames")
            finally:
                if saved_global is None:
                    os.environ.pop("GIT_CONFIG_GLOBAL", None)
                else:
                    os.environ["GIT_CONFIG_GLOBAL"] = saved_global
                if saved_nosystem is None:
                    os.environ.pop("GIT_CONFIG_NOSYSTEM", None)
                else:
                    os.environ["GIT_CONFIG_NOSYSTEM"] = saved_nosystem


if __name__ == "__main__":
    unittest.main()
