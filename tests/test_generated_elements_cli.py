"""Coverage for the generate_image_elements write/check/main CLI surface.

test_generated_elements.py covers the render_* functions against the committed
tree. Nothing covered write(), check(), or main() -- the parts that decide
whether a file is rewritten and what exit code the CI gate returns. These tests
drive that surface against a temporary element tree so they never touch the
repository's own elements/.
"""

import contextlib
import io
from pathlib import Path
import sys
import tempfile
import unittest

ROOT = Path(__file__).parents[1]
sys.path.insert(0, str(ROOT / "scripts"))

import generate_image_elements as gen  # noqa: E402


class TargetTreeTestCase(unittest.TestCase):
    """Redirect _targets() and REPO_ROOT at a throwaway tree."""

    def setUp(self):
        self._tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self._tmp.cleanup)
        self.root = Path(self._tmp.name)
        self.targets = [
            (self.root / "elements" / "demo" / "demo-stack.bst", "stack text\n"),
            (self.root / "elements" / "oci" / "demo.bst", "oci text\n"),
        ]

        real_targets, real_root = gen._targets, gen.REPO_ROOT
        gen._targets = lambda: list(self.targets)
        gen.REPO_ROOT = self.root

        def restore():
            gen._targets = real_targets
            gen.REPO_ROOT = real_root

        self.addCleanup(restore)

    def seed(self):
        """Put every target on disk with exactly its generated content."""
        for path, text in self.targets:
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text(text)


class WriteTests(TargetTreeTestCase):
    def test_write_creates_missing_files_and_parent_directories(self):
        written = gen.write()

        self.assertEqual(written, [path for path, _ in self.targets])
        for path, text in self.targets:
            self.assertEqual(path.read_text(), text)

    def test_write_is_idempotent_on_an_in_sync_tree(self):
        self.seed()

        self.assertEqual(gen.write(), [])

    def test_write_does_not_touch_the_mtime_of_an_in_sync_file(self):
        self.seed()
        path = self.targets[0][0]
        stale_mtime = 100000
        import os

        os.utime(path, (stale_mtime, stale_mtime))

        gen.write()

        self.assertEqual(int(path.stat().st_mtime), stale_mtime)

    def test_write_reverts_a_hand_edited_generated_file(self):
        self.seed()
        edited, expected = self.targets[0]
        edited.write_text("hand edited, silently wrong\n")

        written = gen.write()

        self.assertEqual(written, [edited])
        self.assertEqual(edited.read_text(), expected)

    def test_write_returns_only_the_paths_it_changed(self):
        self.seed()
        drifted = self.targets[1][0]
        drifted.write_text("drift\n")

        self.assertEqual(gen.write(), [drifted])


class CheckTests(TargetTreeTestCase):
    def test_check_is_empty_on_an_in_sync_tree(self):
        self.seed()

        self.assertEqual(gen.check(), [])

    def test_check_reports_a_missing_file(self):
        self.seed()
        missing = self.targets[0][0]
        missing.unlink()

        self.assertEqual(gen.check(), [missing])

    def test_check_reports_a_drifted_file(self):
        self.seed()
        drifted = self.targets[1][0]
        drifted.write_text("drift\n")

        self.assertEqual(gen.check(), [drifted])

    def test_check_does_not_write_anything(self):
        drifted = self.targets[0][0]

        gen.check()

        self.assertFalse(drifted.exists())


class MainTests(TargetTreeTestCase):
    def run_main(self, argv):
        out, err = io.StringIO(), io.StringIO()
        real_argv = sys.argv
        sys.argv = ["generate_image_elements.py", *argv]
        try:
            with contextlib.redirect_stdout(out), contextlib.redirect_stderr(err):
                code = gen.main()
        finally:
            sys.argv = real_argv
        return code, out.getvalue(), err.getvalue()

    def test_write_mode_exits_zero_and_names_every_file_it_wrote(self):
        code, out, err = self.run_main(["--write"])

        self.assertEqual(code, 0)
        self.assertEqual(err, "")
        self.assertIn("wrote elements/demo/demo-stack.bst", out)
        self.assertIn("wrote elements/oci/demo.bst", out)

    def test_write_mode_is_quiet_when_nothing_changed(self):
        self.seed()

        code, out, _ = self.run_main(["--write"])

        self.assertEqual(code, 0)
        self.assertEqual(out, "")

    def test_check_mode_exits_zero_on_an_in_sync_tree(self):
        self.seed()

        code, out, err = self.run_main(["--check"])

        self.assertEqual(code, 0)
        self.assertEqual(err, "")

    def test_check_mode_exits_one_and_reports_the_stale_path_on_stderr(self):
        self.seed()
        self.targets[0][0].write_text("drift\n")

        code, out, err = self.run_main(["--check"])

        self.assertEqual(code, 1)
        self.assertIn("STALE: elements/demo/demo-stack.bst", err)
        self.assertIn("just catalog-write", err)
        self.assertEqual(out, "")

    def test_check_mode_leaves_the_stale_file_alone(self):
        self.seed()
        drifted = self.targets[0][0]
        drifted.write_text("drift\n")

        self.run_main(["--check"])

        self.assertEqual(drifted.read_text(), "drift\n")

    def test_a_mode_is_required(self):
        with self.assertRaises(SystemExit) as raised:
            self.run_main([])
        self.assertEqual(raised.exception.code, 2)

    def test_write_and_check_are_mutually_exclusive(self):
        with self.assertRaises(SystemExit) as raised:
            self.run_main(["--write", "--check"])
        self.assertEqual(raised.exception.code, 2)


class RendererRegistryTests(unittest.TestCase):
    def test_every_record_kind_of_element_has_a_renderer_and_a_path(self):
        self.assertEqual(set(gen.RENDERERS), {"stack", "compose", "oci"})
        for renderer, path_for in gen.RENDERERS.values():
            self.assertTrue(callable(renderer))
            self.assertTrue(callable(path_for))

    def test_renderer_paths_follow_the_committed_layout(self):
        stack = gen.RENDERERS["stack"][1]("demo")
        compose = gen.RENDERERS["compose"][1]("demo")
        oci = gen.RENDERERS["oci"][1]("demo")

        self.assertEqual(stack, gen.ELEMENTS / "demo" / "demo-stack.bst")
        self.assertEqual(compose, gen.ELEMENTS / "demo" / "demo-runtime.bst")
        self.assertEqual(oci, gen.ELEMENTS / "oci" / "demo.bst")

    def test_targets_yields_three_files_per_catalog_record(self):
        import catalog  # noqa: PLC0415

        self.assertEqual(len(gen._targets()), 3 * len(catalog.load_all()))


class YamlSingleQuoteTests(unittest.TestCase):
    def test_plain_value_is_wrapped(self):
        self.assertEqual(gen.yaml_single_quote("hello"), "'hello'")

    def test_apostrophe_is_doubled_so_the_scalar_cannot_be_broken(self):
        import yaml  # noqa: PLC0415

        quoted = gen.yaml_single_quote("bluefin's image")

        self.assertEqual(quoted, "'bluefin''s image'")
        self.assertEqual(yaml.safe_load(f"v: {quoted}")["v"], "bluefin's image")

    def test_non_string_values_are_stringified(self):
        self.assertEqual(gen.yaml_single_quote(7), "'7'")


if __name__ == "__main__":
    unittest.main()
