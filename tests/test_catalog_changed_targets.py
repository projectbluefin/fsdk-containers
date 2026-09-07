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


def git(repo, *args):
    return subprocess.run(
        ["git", *args],
        cwd=repo,
        check=True,
        capture_output=True,
        text=True,
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
        git(self.repo, "commit", "-q", "-m", message)

    def run_gate(self, base=None, head="HEAD"):
        proc = subprocess.run(
            [str(self.script), base or self.base, head],
            cwd=self.repo,
            capture_output=True,
            text=True,
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


if __name__ == "__main__":
    unittest.main()
