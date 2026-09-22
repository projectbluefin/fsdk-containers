"""Executable coverage for the `verify` recipe in the Justfile.

`just verify` is the repo's headline contract gate: AGENTS.md hard rule 4 is
literally "Keep `just verify` green", and `build.yml` runs it on every image
before anything is pushed. `scripts/verify_contract.py` -- the half that
*derives* the gates from the catalog record -- is covered by
`tests/test_verify_contract.py`. The half that *enforces* them is ~190 lines of
bash inside the recipe, and nothing executed a single line of it.

That is the half that fails open. The gate loops accumulate into `failed` and
grep a tar listing; a mistyped `grep -qxF`, a `while ... | read` that loses its
`failed=1` in a subshell, or an `eval` that swallows the contract script's exit
status all produce a recipe that prints "verify passed" for an image that
violates its contract. The Python side cannot see any of that.

These tests run the recipe's real shell body, lifted out of the Justfile at test
time (a copy here would be a second implementation, which by construction cannot
catch the recipe diverging from it), against a stub `podman` and a stub
`scripts/verify_contract.py`. Stubbing the contract script keeps the assertions
about the recipe's behaviour rather than about today's catalog records, which
`tests/test_verify_contract.py` already owns.

Only `bash`, `tar`, `grep` and `paste` are needed -- all of which the recipe
itself already requires. `just` is not a dependency of this suite.
"""

import os
from pathlib import Path
import re
import subprocess
import tarfile
import tempfile
import unittest

ROOT = Path(__file__).parents[1]
JUSTFILE = ROOT / "Justfile"

RECIPE = "verify"

REGISTRY = "registry.invalid/projectbluefin"
LOCAL_TAG = "build"

# A tar listing with the same shape as `podman export | tar -tf -` output for a
# clean distroless image: relative paths, no leading slash.
CLEAN_LISTING = [
    "usr/bin/skopeo",
    "usr/lib/ld-linux-x86-64.so.2",
    "etc/ssl/certs/ca-certificates.crt",
    "usr/share/zoneinfo/UTC",
]


def extract_recipe_body(text, name):
    """Return the shell body of `name` from a Justfile, as a runnable script.

    Raises AssertionError rather than returning something plausible-but-wrong: a
    silently empty body would make every test below pass vacuously.
    """
    lines = text.splitlines()
    start = None
    for i, line in enumerate(lines):
        if re.match(rf"^{re.escape(name)}(\s|:)", line) and line.rstrip().endswith(":"):
            start = i + 1
            break
    if start is None:
        raise AssertionError(
            f"recipe {name!r} not found in the Justfile -- it was renamed or "
            f"removed, and this test no longer covers the contract gate"
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

    # `{{"{{.Size}}"}}` is just's escape for a literal Go template; substitute it
    # before the single-brace interpolations so it is not half-consumed.
    script = script.replace('{{"{{.Size}}"}}', "{{.Size}}")
    script = script.replace("{{sudo_cmd}}", "")
    script = script.replace("{{image_registry}}", REGISTRY)
    script = script.replace("{{image_name}}", "${TEST_IMAGE_NAME}")
    script = script.replace("{{local_tag}}", LOCAL_TAG)

    leftover = re.findall(r"\{\{(?!\.Size)[^{].*?\}\}", script)
    if leftover:
        raise AssertionError(
            f"recipe {name!r} gained unsubstituted just interpolations "
            f"{leftover} -- this harness must learn them before it can claim "
            f"to cover the gate"
        )
    return "#!/usr/bin/env bash\n" + script + "\n"


RECIPE_BODY = extract_recipe_body(JUSTFILE.read_text(), RECIPE)


# A stand-in for `scripts/verify_contract.py <image> --env`. The recipe evals
# whatever this prints, so the fixture is the env block verbatim; the exit
# status is separately controllable to prove the recipe does not swallow it.
CONTRACT_STUB = """#!/usr/bin/env python3
import os
import sys

sys.stdout.write(open(os.environ["STUB_CONTRACT_ENV"]).read())
sys.exit(int(os.environ.get("STUB_CONTRACT_EXIT", "0")))
"""

# A stand-in for podman. Only the four verbs the recipe uses are implemented;
# anything else is a hard error so a new podman call in the recipe cannot pass
# silently. Every `run` invocation is appended to $STUB_RUN_LOG one argument
# per line with a record separator, which is how the argv-integrity assertions
# below see whether mapfile kept a spaced argument intact.
PODMAN_STUB = r"""#!/usr/bin/env bash
set -uo pipefail
verb="${1:-}"
case "$verb" in
    image)
        # image inspect --format {{.Size}} <ref>
        printf '%s\n' "${STUB_SIZE}"
        ;;
    create)
        printf 'stub-container-id\n'
        ;;
    rm)
        ;;
    export)
        cat "${STUB_TAR}"
        ;;
    run)
        shift
        {
            for arg in "$@"; do printf '%s\n' "$arg"; done
            printf -- '--\n'
        } >> "${STUB_RUN_LOG}"
        exit "${STUB_RUN_EXIT:-0}"
        ;;
    *)
        printf 'stub podman: unhandled verb %s\n' "$verb" >&2
        exit 97
        ;;
esac
"""


def contract_env(**overrides):
    """Build a `verify_contract.py --env` block, defaulting to a passing image."""
    values = {
        "IMG_KIND": "distroless",
        "MAX_BYTES": "100000000",
        "FORBID_NAMES": "no shell\nno package manager",
        "FORBID_PATTERNS": "(^|/)(ba|da|z)?sh$\n(^|/)(dnf|apt|rpm)$",
        "REQUIRE_PATHS": "usr/share/zoneinfo/UTC",
        "REQUIRE_ANY_PATHS": "etc/ssl/certs/ca-certificates.crt\netc/pki/tls/certs/ca-bundle.crt",
        "REQUIRE_BINARIES": "",
        "SMOKE_OPTS": "",
        "SMOKE_ARGS": "",
        "SHELL_PROBE": "",
    }
    values.update(overrides)
    return "".join(
        "{}={}\n".format(key, shell_quote(value)) for key, value in values.items()
    )


def shell_quote(value):
    return "'" + str(value).replace("'", "'\\''") + "'"


class VerifyRecipeTestCase(unittest.TestCase):
    """Harness: real recipe body, stub podman, stub contract script."""

    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.work = Path(self.tmp.name)
        self.addCleanup(self.tmp.cleanup)

        self.script = self.work / "verify.sh"
        self.script.write_text(RECIPE_BODY)
        self.script.chmod(0o755)

        bindir = self.work / "bin"
        bindir.mkdir()
        podman = bindir / "podman"
        podman.write_text(PODMAN_STUB)
        podman.chmod(0o755)
        self.bindir = bindir

        # The recipe invokes `python3 scripts/verify_contract.py` relative to the
        # working directory, so the stub goes there rather than on PATH.
        scripts = self.work / "scripts"
        scripts.mkdir()
        contract = scripts / "verify_contract.py"
        contract.write_text(CONTRACT_STUB)
        contract.chmod(0o755)

        self.env_file = self.work / "contract.env"
        self.run_log = self.work / "run.log"
        self.run_log.touch()

    def make_tar(self, members):
        """Write a tar whose member names are exactly `members`."""
        path = self.work / "rootfs.tar"
        with tarfile.open(path, "w") as tf:
            for name in members:
                info = tarfile.TarInfo(name)
                info.size = 0
                tf.addfile(info)
        return path

    def run_verify(
        self,
        listing=None,
        size="1024",
        run_exit="0",
        contract_exit="0",
        image="base",
        **contract_overrides
    ):
        self.env_file.write_text(contract_env(**contract_overrides))
        tar_path = self.make_tar(CLEAN_LISTING if listing is None else listing)

        env = dict(os.environ)
        env.update(
            {
                "PATH": "{}:{}".format(self.bindir, env["PATH"]),
                "TEST_IMAGE_NAME": image,
                "STUB_CONTRACT_ENV": str(self.env_file),
                "STUB_CONTRACT_EXIT": str(contract_exit),
                "STUB_SIZE": str(size),
                "STUB_TAR": str(tar_path),
                "STUB_RUN_LOG": str(self.run_log),
                "STUB_RUN_EXIT": str(run_exit),
            }
        )
        return subprocess.run(
            ["bash", str(self.script)],
            cwd=self.work,
            env=env,
            capture_output=True,
            text=True,
        )

    def run_invocations(self):
        """Return `podman run` argv lists, in call order."""
        raw = self.run_log.read_text().splitlines()
        calls, current = [], []
        for line in raw:
            if line == "--":
                calls.append(current)
                current = []
            else:
                current.append(line)
        return calls

    def assertPassed(self, result):
        self.assertEqual(
            result.returncode,
            0,
            "recipe failed unexpectedly\nstdout:\n{}\nstderr:\n{}".format(
                result.stdout, result.stderr
            ),
        )
        self.assertIn("verify passed", result.stdout)

    def assertFailed(self, result, needle):
        self.assertNotEqual(
            result.returncode,
            0,
            "recipe passed but should have failed\nstdout:\n{}".format(result.stdout),
        )
        self.assertIn(needle, result.stdout + result.stderr)
        self.assertNotIn("verify passed", result.stdout)


class ContractDerivationTests(VerifyRecipeTestCase):
    """The recipe must not swallow the contract script's exit status."""

    def test_clean_distroless_image_passes(self):
        self.assertPassed(self.run_verify())

    def test_contract_script_failure_aborts(self):
        # `eval "$(cmd)"` would discard cmd's status and verify every remaining
        # gate against an empty environment; the recipe assigns first for
        # exactly this reason.
        result = self.run_verify(contract_exit="3")
        self.assertNotEqual(result.returncode, 0)
        self.assertNotIn("verify passed", result.stdout)


class SizeCeilingTests(VerifyRecipeTestCase):
    def test_size_within_ceiling_passes(self):
        result = self.run_verify(size="999", MAX_BYTES="1000")
        self.assertPassed(result)
        self.assertIn("OK: image size 999 bytes", result.stdout)

    def test_size_over_ceiling_fails(self):
        self.assertFailed(
            self.run_verify(size="1001", MAX_BYTES="1000"), "exceeds 1000 bytes"
        )

    def test_size_exactly_at_ceiling_passes(self):
        self.assertPassed(self.run_verify(size="1000", MAX_BYTES="1000"))

    def test_non_numeric_size_fails(self):
        # A podman that prints nothing (or an error) must not be read as 0 and
        # slip under the ceiling.
        self.assertFailed(self.run_verify(size="", MAX_BYTES="1000"), "FAIL")


class ForbiddenPatternGateTests(VerifyRecipeTestCase):
    def test_forbidden_shell_is_detected(self):
        result = self.run_verify(listing=CLEAN_LISTING + ["usr/bin/bash"])
        self.assertFailed(result, "gate 'no shell' violated")

    def test_gate_name_is_paired_with_its_own_pattern(self):
        # FORBID_NAMES and FORBID_PATTERNS are two parallel newline lists
        # stitched back together with paste; a misalignment reports the wrong
        # gate name and makes the failure unactionable.
        result = self.run_verify(listing=CLEAN_LISTING + ["usr/bin/dnf"])
        self.assertFailed(result, "gate 'no package manager' violated")
        self.assertNotIn("gate 'no shell' violated", result.stdout + result.stderr)

    def test_substring_match_does_not_trip_the_shell_gate(self):
        # `usr/bin/sshd` contains "sh" but is not a shell; the anchored pattern
        # must not fire on it.
        self.assertPassed(self.run_verify(listing=CLEAN_LISTING + ["usr/bin/sshd"]))

    def test_empty_gate_list_is_skipped(self):
        self.assertPassed(self.run_verify(FORBID_NAMES="", FORBID_PATTERNS=""))


class RequiredPathGateTests(VerifyRecipeTestCase):
    def test_missing_required_path_fails(self):
        self.assertFailed(
            self.run_verify(REQUIRE_PATHS="usr/share/zoneinfo/UTC\netc/passwd"),
            "required path missing: /etc/passwd",
        )

    def test_required_path_matches_whole_line_only(self):
        # grep -qxF, not grep -qF: a required path must be a tar member in its
        # own right, not a prefix of some deeper file.
        self.assertFailed(
            self.run_verify(
                listing=["usr/share/zoneinfo/UTC/inner"],
                REQUIRE_PATHS="usr/share/zoneinfo/UTC",
                REQUIRE_ANY_PATHS="",
            ),
            "required path missing",
        )

    def test_all_required_paths_present_passes(self):
        self.assertPassed(
            self.run_verify(
                REQUIRE_PATHS="usr/share/zoneinfo/UTC\nusr/bin/skopeo",
            )
        )


class RequireAnyPathGateTests(VerifyRecipeTestCase):
    def test_first_alternative_satisfies_the_gate(self):
        result = self.run_verify()
        self.assertPassed(result)
        self.assertIn("CA alternative present", result.stdout)

    def test_second_alternative_satisfies_the_gate(self):
        result = self.run_verify(
            listing=["usr/share/zoneinfo/UTC", "etc/pki/tls/certs/ca-bundle.crt"]
        )
        self.assertPassed(result)
        self.assertIn("CA alternative present: /etc/pki/tls/certs/ca-bundle.crt", result.stdout)

    def test_no_alternative_present_fails(self):
        self.assertFailed(
            self.run_verify(listing=["usr/share/zoneinfo/UTC"]),
            "none of the required CA alternatives found",
        )

    def test_empty_any_list_is_skipped(self):
        # Shell-enabled records declare no CA alternatives; an empty list must
        # not be read as "zero alternatives matched".
        self.assertPassed(
            self.run_verify(listing=["usr/share/zoneinfo/UTC"], REQUIRE_ANY_PATHS="")
        )


class RequiredBinaryGateTests(VerifyRecipeTestCase):
    def test_missing_binary_fails(self):
        self.assertFailed(
            self.run_verify(REQUIRE_BINARIES="skopeo\nhadolint"),
            "required binary missing: hadolint",
        )

    def test_binary_found_anywhere_in_the_tree_passes(self):
        self.assertPassed(self.run_verify(REQUIRE_BINARIES="skopeo"))

    def test_binary_name_is_not_matched_as_a_suffix(self):
        # `(^|/)name$`: a file called "notskopeo" must not satisfy "skopeo".
        self.assertFailed(
            self.run_verify(
                listing=["usr/share/zoneinfo/UTC", "etc/ssl/certs/ca-certificates.crt",
                         "usr/bin/notskopeo"],
                REQUIRE_BINARIES="skopeo",
            ),
            "required binary missing: skopeo",
        )


class GateAccumulationTests(VerifyRecipeTestCase):
    """Every gate is reported before the recipe exits, not just the first."""

    def test_all_failures_are_reported_in_one_run(self):
        result = self.run_verify(
            listing=["usr/bin/bash"],
            REQUIRE_PATHS="usr/share/zoneinfo/UTC",
            REQUIRE_BINARIES="skopeo",
        )
        combined = result.stdout + result.stderr
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("gate 'no shell' violated", combined)
        self.assertIn("required path missing", combined)
        self.assertIn("none of the required CA alternatives found", combined)
        self.assertIn("required binary missing: skopeo", combined)
        self.assertIn("failed one or more gates", combined)

    def test_failed_gates_skip_the_smoke_test(self):
        # A gate failure must abort before anything is executed: the smoke run
        # would otherwise report a second, confusing error.
        self.run_verify(listing=["usr/bin/bash"], SMOKE_ARGS="--version")
        self.assertEqual(self.run_invocations(), [])


class SmokeTestTests(VerifyRecipeTestCase):
    def test_no_smoke_declared_runs_nothing(self):
        self.assertPassed(self.run_verify())
        self.assertEqual(self.run_invocations(), [])

    def test_smoke_args_follow_the_image_reference(self):
        result = self.run_verify(image="skopeo", SMOKE_ARGS="--version")
        self.assertPassed(result)
        self.assertEqual(
            self.run_invocations(),
            [["--rm", "{}/skopeo:{}".format(REGISTRY, LOCAL_TAG), "--version"]],
        )

    def test_smoke_opts_precede_the_image_reference(self):
        result = self.run_verify(
            image="kubectl",
            SMOKE_OPTS="--entrypoint\n/usr/bin/kubectl",
            SMOKE_ARGS="version\n--client",
        )
        self.assertPassed(result)
        self.assertEqual(
            self.run_invocations(),
            [
                [
                    "--rm",
                    "--entrypoint",
                    "/usr/bin/kubectl",
                    "{}/kubectl:{}".format(REGISTRY, LOCAL_TAG),
                    "version",
                    "--client",
                ]
            ],
        )

    def test_argument_containing_a_space_stays_one_argument(self):
        # The mapfile contract: unquoted $SMOKE_ARGS would word-split this into
        # two arguments and the smoke test would probe something else entirely.
        self.assertPassed(self.run_verify(SMOKE_ARGS="--flag\nwith space"))
        self.assertEqual(self.run_invocations()[0][-2:], ["--flag", "with space"])

    def test_argument_containing_a_glob_is_not_expanded(self):
        (self.work / "expanded-by-mistake.txt").touch()
        self.assertPassed(self.run_verify(SMOKE_ARGS="*.txt"))
        self.assertEqual(self.run_invocations()[0][-1], "*.txt")

    def test_smoke_failure_fails_the_recipe(self):
        self.assertFailed(
            self.run_verify(SMOKE_ARGS="--version", run_exit="1"), "smoke test failed"
        )


class ShellEnabledProbeTests(VerifyRecipeTestCase):
    """Probes gated on IMG_KIND, so any future shell-enabled image inherits them."""

    SHELL_LISTING = ["usr/bin/bash"] + [
        "usr/share/terminfo/{}/entry{}".format("abcdefgh"[i % 8], i) for i in range(1200)
    ]

    def shell_verify(self, **kwargs):
        kwargs.setdefault("listing", self.SHELL_LISTING)
        kwargs.setdefault("IMG_KIND", "shell-enabled")
        kwargs.setdefault("FORBID_NAMES", "")
        kwargs.setdefault("FORBID_PATTERNS", "")
        kwargs.setdefault("REQUIRE_PATHS", "")
        kwargs.setdefault("REQUIRE_ANY_PATHS", "")
        return self.run_verify(**kwargs)

    def test_complete_terminfo_database_passes(self):
        result = self.shell_verify()
        self.assertPassed(result)
        self.assertIn("full terminfo database present (1200 entries)", result.stdout)

    def test_truncated_terminfo_database_fails(self):
        listing = ["usr/bin/bash"] + [
            "usr/share/terminfo/x/entry{}".format(i) for i in range(999)
        ]
        self.assertFailed(
            self.shell_verify(listing=listing), "terminfo database looks incomplete"
        )

    def test_terminfo_is_not_checked_for_distroless_images(self):
        # A distroless image ships no terminfo at all; the count gate must be
        # gated on kind rather than firing on every image.
        result = self.run_verify(IMG_KIND="distroless")
        self.assertPassed(result)
        self.assertNotIn("terminfo", result.stdout)

    def test_shell_enabled_runs_every_execution_probe(self):
        result = self.shell_verify(SHELL_PROBE="true")
        self.assertPassed(result)
        calls = self.run_invocations()
        probes = [call[-1] for call in calls]
        self.assertIn("true", probes)
        self.assertTrue(
            any("shellcheck --version" in p for p in probes),
            "linter suite probe missing: {}".format(probes),
        )
        self.assertTrue(
            any("bwrap --ro-bind / / true" in p for p in probes),
            "bwrap sandbox probe missing: {}".format(probes),
        )
        self.assertTrue(
            any("skopeo inspect" in p for p in probes),
            "skopeo OCI layout probe missing: {}".format(probes),
        )
        self.assertTrue(
            any("tar -czf" in p for p in probes),
            "tar.gz round-trip probe missing: {}".format(probes),
        )

    def test_bwrap_probe_keeps_its_capability(self):
        # Nested user namespaces need SYS_ADMIN from the outer runtime; dropping
        # it would make the probe fail for a reason that has nothing to do with
        # the image.
        self.shell_verify(SHELL_PROBE="true")
        bwrap = [c for c in self.run_invocations() if "bwrap --ro-bind / / true" in c[-1]]
        self.assertEqual(len(bwrap), 1)
        self.assertIn("--cap-add", bwrap[0])
        self.assertIn("SYS_ADMIN", bwrap[0])

    def test_empty_shell_probe_is_skipped(self):
        result = self.shell_verify(SHELL_PROBE="")
        self.assertPassed(result)
        self.assertNotIn("OK: shell_probe passed", result.stdout)

    def test_failing_probe_fails_the_recipe(self):
        self.assertFailed(
            self.shell_verify(SHELL_PROBE="true", run_exit="1"), "FAIL"
        )

    def test_distroless_image_runs_no_shell_probes(self):
        self.assertPassed(self.run_verify())
        self.assertEqual(self.run_invocations(), [])


if __name__ == "__main__":
    unittest.main()
