"""The Python test gate is an allowlist, so prove the allowlist is complete.

`.github/workflows/image-catalog.yml` is the only workflow that runs Python
tests, and it does not discover them: it enumerates filename patterns, one
``python3 -m unittest discover -s tests -p '<glob>'`` step per pattern. The
`Justfile` recipes that mirror it locally do the same. Membership in the suite
is therefore decided by how a file is spelled, not by the fact that it lives in
``tests/``.

That is a fail-open gate. A ``tests/test_*.py`` matching none of the committed
patterns is silently never executed and nothing reports the gap.
``tests/test_renovate_atomic.py`` spent its entire life there: added in
``2afc250``, never run, and by the time it was noticed all three of its
assertions had rotted red against a Renovate design ``renovate.json`` no longer
implements. It was removed in the same change that added this file.

These tests close the hole from inside the gate. They collect every discovery
pattern the repository actually invokes and assert that the set covers every
test module on disk, so the next unreachable file fails CI instead of
disappearing into it.

Two modules are currently run by a ``Justfile`` recipe but by no workflow;
they are recorded in ``KNOWN_LOCAL_ONLY`` below because closing that gap means
editing ``.github/workflows/image-catalog.yml``. The set is a ratchet in both
directions: a new divergence fails, and so does an entry that has stopped being
a real hole.
"""

from pathlib import Path
import fnmatch
import re
import unittest


ROOT = Path(__file__).parents[1]
TESTS_DIR = ROOT / "tests"
JUSTFILE = ROOT / "Justfile"
WORKFLOW_DIR = ROOT / ".github" / "workflows"

# `python3 -m unittest discover -s <dir> -p '<pattern>'`, as written in the
# Justfile and the workflows. Quotes are optional in shell, so both forms are
# accepted; `-s` is captured to ignore any future discovery rooted elsewhere.
DISCOVER_RE = re.compile(
    r"unittest\s+discover\s+-s\s+(?P<start>\S+)\s+-p\s+"
    r"(?P<quote>['\"]?)(?P<pattern>[^'\"\s]+)(?P=quote)"
)


def _discovery_patterns(text):
    """Patterns from every `unittest discover` rooted at `tests` in `text`."""
    return {
        m.group("pattern")
        for m in DISCOVER_RE.finditer(text)
        if m.group("start").rstrip("/") in ("tests", "./tests")
    }


def _sources():
    """Every committed file that can invoke the Python test suite."""
    yield JUSTFILE
    yield from sorted(WORKFLOW_DIR.glob("*.yml"))
    yield from sorted(WORKFLOW_DIR.glob("*.yaml"))


def _test_modules():
    return sorted(p.name for p in TESTS_DIR.glob("test_*.py"))


# Modules that a `Justfile` recipe runs but no workflow does. Each entry is a
# real hole in the merge gate, recorded here only because closing it requires
# editing `.github/workflows/image-catalog.yml`, which is out of scope for the
# change that introduced this file. The set is a ratchet: it may shrink freely,
# and a *new* divergence still fails, but an existing one does not block
# unrelated work. Tracked by issue #226 recommendation 1 (replace the whole
# per-pattern allowlist with one total `discover -p 'test_*.py'`).
KNOWN_LOCAL_ONLY = frozenset(
    {
        "test_donate_clanker_bootstrap.py",  # Justfile `test-donate-clanker`
        "test_skill_index.py",  # Justfile `test-skill-index`
    }
)


class GateCoverageTests(unittest.TestCase):
    def test_every_test_module_is_reachable_by_some_gate_pattern(self):
        modules = _test_modules()
        self.assertTrue(modules, "no tests/test_*.py modules found")

        patterns = set()
        for source in _sources():
            patterns |= _discovery_patterns(source.read_text())
        self.assertTrue(
            patterns,
            "no `unittest discover -s tests -p ...` invocation found in the "
            "Justfile or any workflow: the Python test gate has disappeared",
        )

        unreachable = [
            name
            for name in modules
            if not any(fnmatch.fnmatch(name, pat) for pat in patterns)
        ]
        self.assertEqual(
            unreachable,
            [],
            "tests/ modules matched by no discovery pattern, so they are never "
            "executed by `just` or by CI: "
            f"{unreachable}; committed patterns: {sorted(patterns)}. Either "
            "rename the module to fall under an existing pattern or add a "
            "discovery step that runs it.",
        )

    def test_ci_gate_covers_every_module_the_justfile_covers(self):
        """A green local run must not be broader than the merge gate."""
        just_patterns = _discovery_patterns(JUSTFILE.read_text())
        ci_patterns = set()
        for source in _sources():
            if source == JUSTFILE:
                continue
            ci_patterns |= _discovery_patterns(source.read_text())

        modules = _test_modules()

        def covered(patterns):
            return {
                name
                for name in modules
                if any(fnmatch.fnmatch(name, pat) for pat in patterns)
            }

        local_only = covered(just_patterns) - covered(ci_patterns)
        unrecorded = sorted(local_only - KNOWN_LOCAL_ONLY)
        self.assertEqual(
            unrecorded,
            [],
            "modules run by a Justfile recipe but by no workflow: they gate "
            f"nothing on a pull request: {unrecorded}. Add a discovery step to "
            ".github/workflows/image-catalog.yml, or — only if the gap is "
            "deliberate and tracked — record it in KNOWN_LOCAL_ONLY.",
        )

    def test_known_local_only_exceptions_are_all_still_real(self):
        """The exception set is a ratchet: it must not outlive its holes.

        Once a workflow starts running one of these modules, or the module is
        deleted, the entry has to go — otherwise the set silently accumulates
        permission to diverge.
        """
        just_patterns = _discovery_patterns(JUSTFILE.read_text())
        ci_patterns = set()
        for source in _sources():
            if source == JUSTFILE:
                continue
            ci_patterns |= _discovery_patterns(source.read_text())

        modules = set(_test_modules())

        def covered(patterns):
            return {
                name
                for name in modules
                if any(fnmatch.fnmatch(name, pat) for pat in patterns)
            }

        stale = sorted(KNOWN_LOCAL_ONLY - (covered(just_patterns) - covered(ci_patterns)))
        self.assertEqual(
            stale,
            [],
            "KNOWN_LOCAL_ONLY entries that are no longer local-only (now run by "
            f"a workflow, or deleted): {stale}. Remove them from the set.",
        )

    def test_removed_renovate_guard_has_not_returned_unreachable(self):
        """Regression pin for the file that motivated this gate.

        `tests/test_renovate_atomic.py` matched none of the committed patterns.
        If it is ever restored it must be restored *reachable*; this assertion
        exists so a plain revert cannot quietly recreate a dead test.
        """
        restored = TESTS_DIR / "test_renovate_atomic.py"
        if not restored.exists():
            self.skipTest("obsolete renovate guard is absent, as expected")

        patterns = set()
        for source in _sources():
            patterns |= _discovery_patterns(source.read_text())
        self.assertTrue(
            any(fnmatch.fnmatch(restored.name, pat) for pat in patterns),
            "test_renovate_atomic.py is back but still matches no discovery "
            "pattern; it would not run, exactly as before",
        )


if __name__ == "__main__":
    unittest.main()
