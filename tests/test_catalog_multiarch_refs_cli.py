"""Executed coverage for the check_multiarch_refs CLI gate.

tests/test_catalog_multiarch_refs.py covers the two pure functions
(``extract_arch_refs``, ``check_parity``). Everything that actually wires
those functions to git -- ``get_git_file_content``, ``get_changed_files``
and ``main`` -- had no executed coverage, even though that is exactly the
surface CI depends on:

- .github/workflows/build.yml     : --base <sha> --head HEAD
- .github/workflows/refresh-bst-refs.yml : --base <sha>   (working tree)
- Justfile `check-refs`           : --base <BASE>          (working tree)

These tests build throwaway git repositories on disk and run ``main`` over
them, so both CI invocation modes are exercised for real.

Named ``test_catalog_*`` deliberately: the Justfile `test` recipe discovers
with -p 'test_catalog*.py', so any other prefix would never run in CI.
"""

from pathlib import Path
import io
import contextlib
import os
import subprocess
import sys
import tempfile
import unittest

sys.path.insert(0, str(Path(__file__).parents[1] / "scripts"))

from check_multiarch_refs import (  # noqa: E402
    extract_arch_refs,
    get_changed_files,
    get_git_file_content,
    main,
)


def _bst(x86_ref: str, aarch64_ref: str, version: str = "v1.0.0") -> str:
    return f"""kind: manual
variables:
  tool_version: {version}

sources:
- kind: remote
  (?):
  - arch == "x86_64":
      url: "https://example.com/tool-%{{tool_version}}-x86_64.tar.gz"
      ref: {x86_ref}
  - arch == "aarch64":
      url: "https://example.com/tool-%{{tool_version}}-aarch64.tar.gz"
      ref: {aarch64_ref}
"""


class _GitRepo:
    """A disposable git repository with deterministic, isolated identity."""

    def __init__(self) -> None:
        self._tmp = tempfile.TemporaryDirectory()
        self.path = Path(self._tmp.name)
        self._git("init", "-q", "-b", "main")
        self._git("config", "user.email", "test@example.invalid")
        self._git("config", "user.name", "Test")
        self._git("config", "commit.gpgsign", "false")

    def _git(self, *args: str) -> str:
        return subprocess.check_output(
            ["git", *args],
            cwd=self.path,
            text=True,
            env={
                **os.environ,
                "GIT_CONFIG_GLOBAL": str(self.path / ".gitconfig-none"),
                "GIT_CONFIG_SYSTEM": str(self.path / ".gitconfig-none"),
            },
        )

    def write(self, rel: str, content: str) -> None:
        dest = self.path / rel
        dest.parent.mkdir(parents=True, exist_ok=True)
        dest.write_text(content, encoding="utf-8")

    def remove(self, rel: str) -> None:
        (self.path / rel).unlink()

    def start_orphan_branch(self, name: str) -> None:
        """Begin a disconnected history: no merge base with the current branch."""
        self._git("checkout", "-q", "--orphan", name)
        self._git("rm", "-rq", "--cached", ".")

    def commit(self, message: str) -> str:
        self._git("add", "-A")
        self._git("commit", "-q", "-m", message)
        return self._git("rev-parse", "HEAD").strip()

    def cleanup(self) -> None:
        self._tmp.cleanup()


class MultiarchRefsCliTests(unittest.TestCase):
    def setUp(self) -> None:
        self.repo = _GitRepo()
        self.addCleanup(self.repo.cleanup)
        self._cwd = os.getcwd()
        os.chdir(self.repo.path)
        self.addCleanup(lambda: os.chdir(self._cwd))

    def run_main(self, argv: list[str]) -> tuple[int, str, str]:
        out, err = io.StringIO(), io.StringIO()
        with contextlib.redirect_stdout(out), contextlib.redirect_stderr(err):
            rc = main(argv)
        return rc, out.getvalue(), err.getvalue()

    # ---- get_git_file_content -------------------------------------------

    def test_get_git_file_content_reads_committed_blob(self):
        self.repo.write("elements/tool.bst", _bst("aaa", "bbb"))
        base = self.repo.commit("add tool")

        content = get_git_file_content(base, "elements/tool.bst")

        self.assertIn("ref: aaa", content)

    def test_get_git_file_content_returns_none_for_unknown_path(self):
        self.repo.write("elements/tool.bst", _bst("aaa", "bbb"))
        base = self.repo.commit("add tool")

        self.assertIsNone(get_git_file_content(base, "elements/nope.bst"))

    # ---- get_changed_files ----------------------------------------------

    def test_get_changed_files_lists_bst_changes_between_revisions(self):
        self.repo.write("elements/tool.bst", _bst("aaa", "bbb"))
        self.repo.write("README.md", "hello\n")
        base = self.repo.commit("base")
        self.repo.write("elements/tool.bst", _bst("ccc", "ddd", version="v2.0.0"))
        self.repo.write("README.md", "changed\n")
        head = self.repo.commit("bump")

        changed = get_changed_files(base, head)

        self.assertEqual(changed, ["elements/tool.bst"])

    def test_get_changed_files_sees_working_tree_when_head_is_none(self):
        self.repo.write("elements/tool.bst", _bst("aaa", "bbb"))
        base = self.repo.commit("base")
        self.repo.write("elements/tool.bst", _bst("ccc", "ddd", version="v2.0.0"))

        self.assertEqual(get_changed_files(base, None), ["elements/tool.bst"])

    def test_get_changed_files_empty_when_nothing_changed(self):
        self.repo.write("elements/tool.bst", _bst("aaa", "bbb"))
        base = self.repo.commit("base")

        self.assertEqual(get_changed_files(base, None), [])

    def test_get_changed_files_falls_back_for_unrelated_histories(self):
        """`git diff a...b` needs a merge base; the fallback uses `git diff a b`.

        Two disconnected root commits have no merge base, so the triple-dot
        form fails and the two-dot fallback is what produces the file list.
        """
        self.repo.write("elements/tool.bst", _bst("aaa", "bbb"))
        base = self.repo.commit("base")
        self.repo.start_orphan_branch("other")
        self.repo.write("elements/tool.bst", _bst("ccc", "ddd", version="v2.0.0"))
        other = self.repo.commit("unrelated root")

        self.assertEqual(get_changed_files(base, other), ["elements/tool.bst"])

    # ---- main: --base/--head mode (build.yml) ----------------------------

    def test_main_rejects_asymmetric_bump_between_revisions(self):
        self.repo.write("elements/tool.bst", _bst("aaa", "bbb"))
        base = self.repo.commit("base")
        self.repo.write("elements/tool.bst", _bst("ccc", "bbb", version="v2.0.0"))
        head = self.repo.commit("x86-only bump")

        rc, _, err = self.run_main(["--base", base, "--head", head])

        self.assertEqual(rc, 1)
        self.assertIn("asymmetric multi-arch ref update", err)
        self.assertIn("elements/tool.bst", err)
        self.assertIn("x86_64 changed=True", err)
        self.assertIn("aarch64 changed=False", err)

    def test_main_accepts_symmetric_bump_between_revisions(self):
        self.repo.write("elements/tool.bst", _bst("aaa", "bbb"))
        base = self.repo.commit("base")
        self.repo.write("elements/tool.bst", _bst("ccc", "ddd", version="v2.0.0"))
        head = self.repo.commit("symmetric bump")

        rc, out, _ = self.run_main(["--base", base, "--head", head])

        self.assertEqual(rc, 0)
        self.assertIn("(1 element(s) checked)", out)

    # ---- main: --base only, working tree (refresh-bst-refs.yml, Justfile)

    def test_main_rejects_asymmetric_working_tree_edit(self):
        self.repo.write("elements/tool.bst", _bst("aaa", "bbb"))
        base = self.repo.commit("base")
        self.repo.write("elements/tool.bst", _bst("ccc", "bbb", version="v2.0.0"))

        rc, _, err = self.run_main(["--base", base])

        self.assertEqual(rc, 1)
        self.assertIn("asymmetric multi-arch ref update", err)

    def test_main_accepts_symmetric_working_tree_edit(self):
        self.repo.write("elements/tool.bst", _bst("aaa", "bbb"))
        base = self.repo.commit("base")
        self.repo.write("elements/tool.bst", _bst("ccc", "ddd", version="v2.0.0"))

        rc, out, _ = self.run_main(["--base", base])

        self.assertEqual(rc, 0)
        self.assertIn("(1 element(s) checked)", out)

    def test_main_reports_zero_checked_when_no_elements_changed(self):
        self.repo.write("elements/tool.bst", _bst("aaa", "bbb"))
        base = self.repo.commit("base")

        rc, out, _ = self.run_main(["--base", base])

        self.assertEqual(rc, 0)
        self.assertIn("(0 element(s) checked)", out)

    # ---- main: explicit file arguments -----------------------------------

    def test_main_checks_explicitly_named_files(self):
        self.repo.write("elements/tool.bst", _bst("aaa", "bbb"))
        base = self.repo.commit("base")
        self.repo.write("elements/tool.bst", _bst("ccc", "bbb", version="v2.0.0"))

        rc, _, err = self.run_main(["--base", base, "elements/tool.bst"])

        self.assertEqual(rc, 1)
        self.assertIn("elements/tool.bst", err)

    def test_main_skips_non_bst_arguments(self):
        self.repo.write("README.md", "hello\n")
        base = self.repo.commit("base")
        self.repo.write("README.md", "changed\n")

        rc, out, _ = self.run_main(["--base", base, "README.md"])

        self.assertEqual(rc, 0)
        self.assertIn("(0 element(s) checked)", out)

    def test_main_skips_files_absent_from_base(self):
        self.repo.write("README.md", "hello\n")
        base = self.repo.commit("base")
        self.repo.write("elements/new.bst", _bst("aaa", "bbb"))

        rc, out, _ = self.run_main(["--base", base, "elements/new.bst"])

        self.assertEqual(rc, 0)
        self.assertIn("(0 element(s) checked)", out)

    def test_main_skips_files_deleted_from_working_tree(self):
        self.repo.write("elements/tool.bst", _bst("aaa", "bbb"))
        base = self.repo.commit("base")
        self.repo.remove("elements/tool.bst")

        rc, out, _ = self.run_main(["--base", base, "elements/tool.bst"])

        self.assertEqual(rc, 0)
        self.assertIn("(0 element(s) checked)", out)

    def test_main_skips_files_deleted_at_head_revision(self):
        self.repo.write("elements/tool.bst", _bst("aaa", "bbb"))
        self.repo.write("README.md", "hello\n")
        base = self.repo.commit("base")
        self.repo.remove("elements/tool.bst")
        head = self.repo.commit("drop tool")

        rc, out, _ = self.run_main(
            ["--base", base, "--head", head, "elements/tool.bst"]
        )

        self.assertEqual(rc, 0)
        self.assertIn("(0 element(s) checked)", out)

    def test_main_aggregates_errors_across_multiple_elements(self):
        self.repo.write("elements/one.bst", _bst("aaa", "bbb"))
        self.repo.write("elements/two.bst", _bst("111", "222"))
        base = self.repo.commit("base")
        self.repo.write("elements/one.bst", _bst("ccc", "bbb", version="v2.0.0"))
        self.repo.write("elements/two.bst", _bst("111", "333", version="v2.0.0"))
        head = self.repo.commit("both asymmetric")

        rc, _, err = self.run_main(["--base", base, "--head", head])

        self.assertEqual(rc, 1)
        self.assertIn("elements/one.bst", err)
        self.assertIn("elements/two.bst", err)
        self.assertEqual(err.count("ERROR:"), 2)

    def test_main_checks_nested_element_paths(self):
        self.repo.write("elements/lab-runner/kubectl.bst", _bst("aaa", "bbb"))
        base = self.repo.commit("base")
        self.repo.write(
            "elements/lab-runner/kubectl.bst", _bst("ccc", "bbb", version="v2.0.0")
        )

        rc, _, err = self.run_main(["--base", base])

        self.assertEqual(rc, 1)
        self.assertIn("elements/lab-runner/kubectl.bst", err)

    def test_main_ignores_single_arch_elements(self):
        single = """kind: manual
sources:
- kind: remote
  url: "https://example.com/tool.tar.gz"
  ref: aaa
"""
        self.repo.write("elements/single.bst", single)
        base = self.repo.commit("base")
        self.repo.write("elements/single.bst", single.replace("ref: aaa", "ref: ccc"))

        rc, out, _ = self.run_main(["--base", base])

        self.assertEqual(rc, 0)
        self.assertIn("(1 element(s) checked)", out)


class MalformedElementTests(unittest.TestCase):
    """extract_arch_refs must degrade to {} rather than raise on junk input.

    A .bst file that is mid-edit, templated, or simply not a mapping reaches
    this gate on every PR; an exception here fails CI with a traceback
    instead of a verdict.
    """

    def test_unparseable_yaml_yields_no_refs(self):
        self.assertEqual(extract_arch_refs("key: [unclosed\n"), {})

    def test_non_mapping_document_yields_no_refs(self):
        self.assertEqual(extract_arch_refs("- just\n- a\n- list\n"), {})

    def test_absent_or_null_sources_yields_no_refs(self):
        # Both shapes collapse to the same `doc.get("sources") or []`: a
        # document with no `sources` key, and one whose `sources` is null.
        for content in ("kind: manual\n", "sources:\n"):
            with self.subTest(content=content):
                self.assertEqual(extract_arch_refs(content), {})

    def test_non_mapping_source_entry_is_skipped(self):
        self.assertEqual(extract_arch_refs("sources:\n- just-a-string\n"), {})

    def test_non_list_conditional_is_skipped(self):
        content = 'sources:\n- kind: remote\n  "(?)": not-a-list\n'
        self.assertEqual(extract_arch_refs(content), {})

    def test_non_mapping_conditional_entry_is_skipped(self):
        content = 'sources:\n- kind: remote\n  "(?)":\n  - just-a-string\n'
        self.assertEqual(extract_arch_refs(content), {})

    def test_non_mapping_condition_body_is_skipped(self):
        content = 'sources:\n- kind: remote\n  "(?)":\n  - \'arch == "x86_64"\': nope\n'
        self.assertEqual(extract_arch_refs(content), {})

    def test_condition_without_arch_equality_is_skipped(self):
        content = (
            'sources:\n- kind: remote\n  "(?)":\n'
            "  - 'target_arch != \"x86_64\"':\n      ref: aaa\n"
        )
        self.assertEqual(extract_arch_refs(content), {})

    def test_arch_condition_without_ref_is_skipped(self):
        content = (
            'sources:\n- kind: remote\n  "(?)":\n'
            "  - 'arch == \"x86_64\"':\n      url: https://example.com/t.tar.gz\n"
        )
        self.assertEqual(extract_arch_refs(content), {})


if __name__ == "__main__":
    unittest.main()
