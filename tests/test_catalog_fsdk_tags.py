"""Executable coverage for the FSDK version derivation and the `tags` recipe.

Every published image tag comes from two pieces of the Justfile: the
`fsdk_version` backtick expression, which parses the release out of the pinned
`ref:` in `elements/freedesktop-sdk.bst`, and the `tags` recipe, which turns
that release into the tag set. `oci-images.yml` publishes every line `just tags`
prints and treats the last line as the immutable point-release tag it skips
when already published; `vulnerability-scan.yml` scans that same last line.

A regression here mis-tags every image at once (a `latest` tag, a lost minor
line, or the minor line treated as the immutable point tag), and nothing
asserts it before a push to `main` publishes the result.

These tests run the real expressions, lifted out of the Justfile at test time,
against the junction ref formats the repository has actually pinned. `just`
is not a dependency of this suite.
"""

from pathlib import Path
import re
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).parents[1]
JUSTFILE = ROOT / "Justfile"
JUNCTION = ROOT / "elements" / "freedesktop-sdk.bst"


def backtick_expr(text, name):
    """Return the shell command of `export <name> := `...`` in the Justfile."""
    m = re.search(rf"^export {re.escape(name)} := `(.*)`$", text, re.MULTILINE)
    if m is None:
        raise AssertionError(f"`export {name} := `...`` not found in the Justfile")
    return m.group(1)


def recipe_body(text, name):
    """Return the shell body of recipe `name` with `{{fsdk_version}}` as $V_IN."""
    lines = text.splitlines()
    start = None
    for i, line in enumerate(lines):
        if re.match(rf"^{re.escape(name)}:\s*$", line):
            start = i + 1
            break
    if start is None:
        raise AssertionError(f"recipe {name!r} not found in the Justfile")
    body = []
    for line in lines[start:]:
        if line.strip() and not line.startswith((" ", "\t")):
            break
        body.append(line[4:] if line.startswith("    ") else line.lstrip())
    if body and body[0].startswith("#!"):
        body = body[1:]
    script = "\n".join(body).strip("\n")
    script = script.replace("{{fsdk_version}}", "${V_IN}")
    leftover = re.findall(r"\{\{.*?\}\}", script)
    if leftover:
        raise AssertionError(
            f"recipe {name!r} gained unsubstituted just interpolations {leftover}"
        )
    return script


TEXT = JUSTFILE.read_text()
VERSION_EXPR = backtick_expr(TEXT, "fsdk_version")
REF_EXPR = backtick_expr(TEXT, "fsdk_ref")
TAGS_BODY = recipe_body(TEXT, "tags")

SHA = "32c5fea70e827885fc805d38a9dc5716c39ed173"


def junction(ref):
    return (
        "kind: junction\n"
        "sources:\n"
        "- kind: git_repo\n"
        "  url: gitlab:freedesktop-sdk/freedesktop-sdk.git\n"
        "  track: freedesktop-sdk-26.08*\n"
        f"  ref: {ref}\n"
    )


def run_expr(expr, bst_text):
    """Run a Justfile backtick expression from a tree holding `bst_text`."""
    with tempfile.TemporaryDirectory() as tmp:
        (Path(tmp) / "elements").mkdir()
        (Path(tmp) / "elements" / "freedesktop-sdk.bst").write_text(bst_text)
        out = subprocess.run(
            ["bash", "-c", expr], cwd=tmp, capture_output=True, text=True, check=True
        )
    return out.stdout.strip()


def run_tags(version):
    return subprocess.run(
        ["bash", "-c", TAGS_BODY],
        env={"PATH": "/usr/bin:/bin", "V_IN": version},
        capture_output=True,
        text=True,
    )


class FsdkVersionTest(unittest.TestCase):
    # Every ref format elements/freedesktop-sdk.bst has pinned so far.
    CASES = {
        f"freedesktop-sdk-25.08.15-0-g{SHA}": "25.08.15",
        f"freedesktop-sdk-26.08beta.2-0-g{SHA}": "26.08beta.2",
        f"freedesktop-sdk-26.08rc.1-0-g{SHA}": "26.08rc.1",
        f"freedesktop-sdk-26.08.0-0-g{SHA}": "26.08.0",
        f"freedesktop-sdk-26.08.2-0-g{SHA}": "26.08.2",
        # Commits past the tag keep the release, drop the describe suffix.
        f"freedesktop-sdk-26.08.2-14-g{SHA[:12]}": "26.08.2",
    }

    def test_release_is_parsed_from_describe_ref(self):
        for ref, want in self.CASES.items():
            with self.subTest(ref=ref):
                self.assertEqual(run_expr(VERSION_EXPR, junction(ref)), want)

    def test_full_ref_is_kept_for_provenance(self):
        for ref in self.CASES:
            with self.subTest(ref=ref):
                self.assertEqual(run_expr(REF_EXPR, junction(ref)), ref)

    def test_only_first_ref_line_is_read(self):
        bst = junction(f"freedesktop-sdk-26.08.2-0-g{SHA}") + (
            "- kind: patch_queue\n"
            "  path: patches/freedesktop-sdk\n"
            f"  ref: freedesktop-sdk-99.99.9-0-g{SHA}\n"
        )
        self.assertEqual(run_expr(VERSION_EXPR, bst), "26.08.2")
        self.assertEqual(
            run_expr(REF_EXPR, bst), f"freedesktop-sdk-26.08.2-0-g{SHA}"
        )

    def test_pinned_junction_yields_a_taggable_release(self):
        version = run_expr(VERSION_EXPR, JUNCTION.read_text())
        self.assertRegex(version, r"^\d{2}\.\d{2}(\.\d+|(alpha|beta|rc)\.\d+)?$")


class TagsRecipeTest(unittest.TestCase):
    def tags(self, version):
        out = run_tags(version)
        self.assertEqual(out.returncode, 0, out.stderr)
        return out.stdout.splitlines()

    def test_point_release_publishes_minor_line_then_point_tag(self):
        self.assertEqual(self.tags("26.08.2"), ["26.08", "26.08.2"])
        self.assertEqual(self.tags("25.08.15"), ["25.08", "25.08.15"])

    def test_dot_zero_release_keeps_its_own_point_tag(self):
        self.assertEqual(self.tags("26.08.0"), ["26.08", "26.08.0"])

    def test_pre_release_publishes_minor_line_then_pre_release_tag(self):
        self.assertEqual(self.tags("26.08beta.2"), ["26.08", "26.08beta.2"])
        self.assertEqual(self.tags("26.08rc.1"), ["26.08", "26.08rc.1"])

    def test_bare_minor_line_is_published_once(self):
        self.assertEqual(self.tags("26.08"), ["26.08"])

    def test_last_line_is_the_immutable_tag(self):
        # oci-images.yml and vulnerability-scan.yml read `just tags | tail -1`
        # as the point tag; the minor line must never be last when they differ.
        for version in ("25.08.15", "26.08.0", "26.08beta.2", "26.08rc.1"):
            with self.subTest(version=version):
                self.assertEqual(self.tags(version)[-1], version)

    def test_never_publishes_latest(self):
        for version in ("25.08.15", "26.08beta.2", "26.08"):
            with self.subTest(version=version):
                self.assertNotIn("latest", self.tags(version))

    def test_unparseable_version_fails_instead_of_tagging(self):
        # A ref that is not a release (e.g. a bare commit) must stop the
        # publish job rather than emit a tag set without a minor line.
        for version in (SHA, "", "main"):
            with self.subTest(version=version):
                out = run_tags(version)
                self.assertNotEqual(out.returncode, 0, out.stdout)
                self.assertEqual(out.stdout, "")


if __name__ == "__main__":
    unittest.main()
