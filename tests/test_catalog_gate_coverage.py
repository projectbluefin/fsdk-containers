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

A workflow reaches the suite in one of two ways, and both count. It can spell
the ``unittest discover`` invocation itself, as ``image-catalog.yml`` and
``skill-catalog.yml`` do, or it can ``run: just <recipe>`` and let the recipe
spell it, as ``build.yml``'s ``pr-guest-contract`` job does with
``just podman-vm-check``. Reading only the literal invocations misreports the
second form as an uncovered hole, so the CI side resolves ``just`` recipe names
(transitively through recipe dependencies) into the Justfile bodies they run.

``KNOWN_LOCAL_ONLY`` records modules a ``Justfile`` recipe runs but no workflow
does. The set is a ratchet in both directions: a new divergence fails, and so
does an entry that has stopped being a real hole. It is currently empty.
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

# `just <recipe>` as written in a workflow `run:` step, possibly behind
# leading `VAR=value` assignments (e.g. `BUILD_IMAGE_NAME=base just build`).
# Only the recipe name is captured; its arguments are irrelevant here.
JUST_CALL_RE = re.compile(r"(?:^|[|&;(]|\s)just\s+(?P<recipe>[A-Za-z0-9_][\w-]*)")

# Start of a Justfile recipe: `name arg1 *ARGS: dep1 dep2`, at column zero.
# Attributes (`[group('test')]`) and settings lines are not recipes.
JUST_RECIPE_RE = re.compile(
    r"^(?P<name>[A-Za-z0-9_][\w-]*)(?P<params>[^:=\n]*):(?!=)(?P<deps>[^\n]*)$"
)


def _strip_yaml_comments(text):
    """Drop whole-line YAML comments so prose cannot look like a command."""
    return "\n".join(
        line for line in text.splitlines() if not line.lstrip().startswith("#")
    )


def _just_recipes(text):
    """Map every Justfile recipe name to its (body, dependency names)."""
    recipes = {}
    lines = text.splitlines()
    for index, line in enumerate(lines):
        if not line or line[0].isspace():
            continue
        match = JUST_RECIPE_RE.match(line)
        if not match:
            continue
        body = []
        for following in lines[index + 1 :]:
            if following.strip() and not following[0].isspace():
                break
            body.append(following)
        deps = [
            token
            for token in match.group("deps").split()
            if re.fullmatch(r"[A-Za-z0-9_][\w-]*", token)
        ]
        recipes[match.group("name")] = ("\n".join(body), deps)
    return recipes


def _recipe_text(names, recipes):
    """Bodies of `names` plus everything they depend on, transitively."""
    seen = set()
    pending = list(names)
    chunks = []
    while pending:
        name = pending.pop()
        if name in seen or name not in recipes:
            continue
        seen.add(name)
        body, deps = recipes[name]
        chunks.append(body)
        pending.extend(deps)
    return "\n".join(chunks)


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
    yield from _workflow_sources()


def _workflow_sources():
    yield from sorted(WORKFLOW_DIR.glob("*.yml"))
    yield from sorted(WORKFLOW_DIR.glob("*.yaml"))


def _ci_patterns():
    """Discovery patterns a workflow runs, directly or through `just`."""
    patterns = set()
    invoked_recipes = set()
    for source in _workflow_sources():
        text = _strip_yaml_comments(source.read_text())
        patterns |= _discovery_patterns(text)
        invoked_recipes |= {
            match.group("recipe") for match in JUST_CALL_RE.finditer(text)
        }
    recipes = _just_recipes(JUSTFILE.read_text())
    patterns |= _discovery_patterns(_recipe_text(invoked_recipes, recipes))
    return patterns


def _test_modules():
    return sorted(p.name for p in TESTS_DIR.glob("test_*.py"))


# Modules a `Justfile` recipe runs but no workflow does, directly or through a
# `run: just <recipe>` step. Each entry would be a real hole in the merge gate.
# The set is a ratchet: it may shrink freely, a *new* divergence still fails,
# and an entry that has stopped being a hole must be removed. It is empty —
# every module on disk is reachable from some workflow.
KNOWN_LOCAL_ONLY = frozenset()


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
        ci_patterns = _ci_patterns()

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
            "a workflow, or a `run: just <recipe>` step that reaches them, or "
            "— only if the gap is deliberate and tracked — record it in "
            "KNOWN_LOCAL_ONLY.",
        )

    def test_known_local_only_exceptions_are_all_still_real(self):
        """The exception set is a ratchet: it must not outlive its holes.

        Once a workflow starts running one of these modules, or the module is
        deleted, the entry has to go — otherwise the set silently accumulates
        permission to diverge.
        """
        just_patterns = _discovery_patterns(JUSTFILE.read_text())
        ci_patterns = _ci_patterns()

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


class JustResolutionTests(unittest.TestCase):
    """Unit coverage for the `just`-following half of the CI-side model."""

    JUSTFILE_SAMPLE = "\n".join(
        [
            "set shell := ['bash', '-c']",
            "",
            "[group('test')]",
            "podman-vm-check: prereq",
            "    python3 -m unittest discover -s tests -p 'test_donate_clanker*.py' -v",
            "    tests/podman-vm-contract.sh",
            "",
            "prereq:",
            "    python3 -m unittest discover -s tests -p 'test_prereq*.py' -v",
            "",
            "unused:",
            "    python3 -m unittest discover -s tests -p 'test_unused*.py' -v",
            "",
            "bst *ARGS:",
            "    echo {{ARGS}}",
        ]
    )

    def test_recipes_are_parsed_with_bodies_and_dependencies(self):
        recipes = _just_recipes(self.JUSTFILE_SAMPLE)
        self.assertEqual(
            set(recipes), {"podman-vm-check", "prereq", "unused", "bst"}
        )
        body, deps = recipes["podman-vm-check"]
        self.assertIn("test_donate_clanker*.py", body)
        self.assertEqual(deps, ["prereq"])
        self.assertEqual(recipes["bst"][1], [])

    def test_assignments_and_attributes_are_not_recipes(self):
        recipes = _just_recipes(self.JUSTFILE_SAMPLE)
        self.assertNotIn("set", recipes)
        self.assertNotIn("[group('test')]", recipes)

    def test_recipe_text_follows_dependencies_transitively(self):
        recipes = _just_recipes(self.JUSTFILE_SAMPLE)
        text = _recipe_text(["podman-vm-check"], recipes)
        self.assertEqual(
            _discovery_patterns(text),
            {"test_donate_clanker*.py", "test_prereq*.py"},
        )

    def test_recipe_text_ignores_unknown_recipe_names(self):
        recipes = _just_recipes(self.JUSTFILE_SAMPLE)
        self.assertEqual(_recipe_text(["no-such-recipe"], recipes), "")

    def test_just_call_matches_recipe_behind_env_assignments(self):
        found = {
            m.group("recipe")
            for m in JUST_CALL_RE.finditer("run: BUILD_IMAGE_NAME=base just verify")
        }
        self.assertEqual(found, {"verify"})

    def test_just_call_ignores_a_bare_tool_declaration(self):
        self.assertIsNone(JUST_CALL_RE.search("          tool: just\n"))

    def test_yaml_comments_cannot_supply_a_pattern(self):
        text = _strip_yaml_comments(
            "  # run: python3 -m unittest discover -s tests -p 'test_ghost*.py'\n"
            "  run: python3 -m unittest discover -s tests -p 'test_real*.py'\n"
        )
        self.assertEqual(_discovery_patterns(text), {"test_real*.py"})

    def test_repository_ci_patterns_include_a_just_only_invocation(self):
        """The live tree proves the indirection is exercised, not hypothetical.

        `build.yml`'s `pr-guest-contract` job runs `just podman-vm-check`; no
        workflow spells that discovery pattern itself. Reading only literal
        invocations reported it as an uncovered hole.
        """
        literal = set()
        for source in _workflow_sources():
            literal |= _discovery_patterns(_strip_yaml_comments(source.read_text()))
        self.assertNotIn("test_donate_clanker*.py", literal)
        self.assertIn("test_donate_clanker*.py", _ci_patterns())


if __name__ == "__main__":
    unittest.main()
