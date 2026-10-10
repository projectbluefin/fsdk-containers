"""Executable coverage for the `compress-podman-vm` and `publish-podman-vm` recipes.

`vm-guest.yml` runs both recipes to put the donate-clanker VM disks on the FSDK
point release. `publish-podman-vm` claims to be an all-or-nothing transaction
per architecture: preflight (every asset present and under GitHub's 2 GiB
limit), repair of a partial set, rollback of everything it uploaded on any
failure, and a post-upload size check. A complete set must never be
overwritten.

Every one of those branches only runs when something has already gone wrong on
a real release, so CI never exercises them. A regression in any of them leaves
a checksum on the release without its disk, overwrites an immutable asset, or
deletes the other architecture's assets.

These tests run the recipes' real shell bodies, lifted out of the Justfile at
test time, against a stub `gh` that keeps a fake release on disk and a stub
`zstd`. `just` is not a dependency of this suite.
"""

import hashlib
import os
from pathlib import Path
import re
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).parents[1]
JUSTFILE = ROOT / "Justfile"

FSDK_VERSION = "25.08.99"
TAG = "v" + FSDK_VERSION
LIMIT = 2147483648


def extract_recipe_body(text, name):
    """Return the shell body of `name` from the Justfile as a runnable script."""
    lines = text.splitlines()
    start = None
    for i, line in enumerate(lines):
        if re.match(rf"^{re.escape(name)}(\s|:)", line) and line.rstrip().endswith(":"):
            start = i + 1
            break
    if start is None:
        raise AssertionError(f"recipe {name!r} not found in the Justfile")

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
    script = script.replace("{{fsdk_version}}", FSDK_VERSION)
    leftover = re.findall(r"\{\{[^{].*?\}\}", script)
    if leftover:
        raise AssertionError(
            f"recipe {name!r} gained unsubstituted just interpolations {leftover}"
        )
    return "#!/usr/bin/env bash\n" + script + "\n"


PUBLISH_BODY = extract_recipe_body(JUSTFILE.read_text(), "publish-podman-vm")
COMPRESS_BODY = extract_recipe_body(JUSTFILE.read_text(), "compress-podman-vm")


# A fake `gh release`. The release lives in $STUB_RELEASE: the directory exists
# once the release does, and each asset is a file in it. Every call is logged
# to $STUB_GH_LOG. Failure injection:
#   STUB_UPLOAD_FAIL=<name>   upload of that asset fails without storing it
#   STUB_SHORT_UPLOAD=<name>  that asset is stored one byte short
# Any verb the recipe does not use is a hard error.
GH_STUB = r"""#!/usr/bin/env bash
set -uo pipefail
printf '%s\n' "$*" >> "${STUB_GH_LOG}"
rel="${STUB_RELEASE}"
[ "$1" = release ] || { echo "stub gh: unhandled $*" >&2; exit 97; }
verb="$2"; tag="$3"
[ "$tag" = "${STUB_TAG}" ] || { echo "stub gh: unexpected tag $tag" >&2; exit 96; }
case "$verb" in
    view)
        [ -d "$rel" ] || { echo "release not found" >&2; exit 1; }
        if [ "$#" -eq 3 ]; then exit 0; fi
        jq_expr="${@: -1}"
        for f in "$rel"/*; do
            [ -e "$f" ] || continue
            n="$(basename "$f")"
            case "$jq_expr" in
                '.assets[].name') printf '%s\n' "$n" ;;
                *'.size'*) printf '%s %s\n' "$n" "$(stat -c %s "$f")" ;;
                *) echo "stub gh: unhandled jq $jq_expr" >&2; exit 95 ;;
            esac
        done
        ;;
    create)
        mkdir "$rel"
        ;;
    upload)
        f="$4"; n="$(basename "$f")"
        [ -d "$rel" ] || exit 1
        [ ! -e "$rel/$n" ] || { echo "asset $n already exists" >&2; exit 1; }
        if [ "$n" = "${STUB_UPLOAD_FAIL:-}" ]; then echo "upload failed" >&2; exit 1; fi
        if [ "$n" = "${STUB_SHORT_UPLOAD:-}" ]; then
            head -c "$(( $(stat -c %s "$f") - 1 ))" "$f" > "$rel/$n"
        else
            cp "$f" "$rel/$n"
        fi
        ;;
    delete-asset)
        rm "$rel/$4"
        ;;
    *)
        echo "stub gh: unhandled verb $verb" >&2; exit 97
        ;;
esac
"""

# A stand-in for zstd: `zstd ... <in> -o <out>` copies in to out and logs argv.
ZSTD_STUB = r"""#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" >> "${STUB_ZSTD_LOG}"
out=""; in=""
while [ "$#" -gt 0 ]; do
    case "$1" in
        -o) out="$2"; shift 2 ;;
        -*) shift ;;
        *) in="$1"; shift ;;
    esac
done
cp "$in" "$out"
"""


def raw_name(arch):
    return f"donate-clanker-vm-{FSDK_VERSION}-{arch}.raw"


def qcow2_name(arch):
    return f"donate-clanker-vm-{FSDK_VERSION}-{arch}.qcow2"


def asset_names(arch, qcow2=False):
    names = [raw_name(arch) + s for s in (".zst", ".zst.sha256", ".sha256")]
    if qcow2:
        names += [qcow2_name(arch) + s for s in (".zst", ".zst.sha256", ".sha256")]
    names.append(f"podman-vm-{arch}.spdx.json")
    return names


class RecipeTestCase(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.work = Path(self.tmp.name)
        self.dist = self.work / "dist-vm"
        self.dist.mkdir()
        self.release = self.work / "release"
        self.gh_log = self.work / "gh.log"
        self.gh_log.touch()

        self.bin = self.work / "bin"
        self.bin.mkdir()
        for name, body in (("gh", GH_STUB), ("zstd", ZSTD_STUB)):
            stub = self.bin / name
            stub.write_text(body)
            stub.chmod(0o755)

        for name, body in (("publish.sh", PUBLISH_BODY), ("compress.sh", COMPRESS_BODY)):
            script = self.work / name
            script.write_text(body)
            script.chmod(0o755)

    def env(self, **extra):
        env = dict(os.environ)
        env.update(
            PATH=f"{self.bin}:{os.environ['PATH']}",
            STUB_GH_LOG=str(self.gh_log),
            STUB_ZSTD_LOG=str(self.work / "zstd.log"),
            STUB_RELEASE=str(self.release),
            STUB_TAG=TAG,
        )
        env.update(extra)
        return env

    def run_script(self, name, env=None):
        return subprocess.run(
            [str(self.work / name)],
            cwd=self.work,
            env=env or self.env(),
            capture_output=True,
            text=True,
            timeout=60,
        )

    def stage(self, arch="x86_64", qcow2=False, skip=()):
        """Write a complete asset set for `arch` into dist-vm/, minus `skip`."""
        disks = [raw_name(arch)] + ([qcow2_name(arch)] if qcow2 else [])
        for disk in disks:
            (self.dist / disk).write_bytes(b"disk " + disk.encode())
        for name in asset_names(arch, qcow2):
            if name not in skip:
                (self.dist / name).write_bytes(f"content of {name}\n".encode())

    def publish_existing(self, names, content=b"old\n"):
        self.release.mkdir(exist_ok=True)
        for name in names:
            (self.release / name).write_bytes(content)

    def released(self):
        if not self.release.is_dir():
            return set()
        return {p.name for p in self.release.iterdir()}

    def gh_calls(self):
        return self.gh_log.read_text().splitlines()


class PublishPreflightTest(RecipeTestCase):
    def assert_refused_before_gh(self, result, message):
        self.assertNotEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn(message, result.stderr)
        self.assertEqual(self.gh_calls(), [], "preflight failure must not reach gh")

    def test_no_raw_disk_fails(self):
        self.assert_refused_before_gh(
            self.run_script("publish.sh"), "expected exactly one raw VM disk"
        )

    def test_two_raw_disks_fail(self):
        self.stage("x86_64")
        self.stage("aarch64")
        self.assert_refused_before_gh(
            self.run_script("publish.sh"), "expected exactly one raw VM disk"
        )

    def test_two_qcow2_disks_fail(self):
        self.stage("x86_64", qcow2=True)
        (self.dist / qcow2_name("aarch64")).write_bytes(b"x")
        self.assert_refused_before_gh(
            self.run_script("publish.sh"), "at most one QCOW2"
        )

    def test_each_missing_asset_fails_before_any_upload(self):
        for missing in asset_names("x86_64", qcow2=True):
            with self.subTest(missing=missing):
                shutil.rmtree(self.dist)
                self.dist.mkdir()
                self.gh_log.write_text("")
                self.stage("x86_64", qcow2=True, skip=(missing,))
                self.assert_refused_before_gh(
                    self.run_script("publish.sh"), f"{missing} not found"
                )

    def test_asset_at_the_github_limit_fails_before_any_upload(self):
        self.stage("x86_64")
        big = self.dist / (raw_name("x86_64") + ".zst")
        with open(big, "wb") as f:
            f.truncate(LIMIT)
        self.assert_refused_before_gh(
            self.run_script("publish.sh"), f"GitHub rejects release assets of {LIMIT}"
        )

    def test_asset_one_byte_under_the_limit_passes_preflight(self):
        self.stage("x86_64")
        big = self.dist / (raw_name("x86_64") + ".zst.sha256")
        with open(big, "wb") as f:
            f.truncate(LIMIT - 1)
        # Skip the costly copy: fail the first upload instead and only assert
        # that preflight let the run reach gh.
        result = self.run_script(
            "publish.sh", self.env(STUB_UPLOAD_FAIL=raw_name("x86_64") + ".zst")
        )
        self.assertNotEqual(result.returncode, 0)
        self.assertNotIn("GitHub rejects", result.stderr)
        self.assertTrue(any(c.startswith("release upload") for c in self.gh_calls()))


class PublishTransactionTest(RecipeTestCase):
    def test_fresh_release_is_created_and_receives_the_full_set(self):
        self.stage("x86_64", qcow2=True)
        result = self.run_script("publish.sh")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.released(), set(asset_names("x86_64", qcow2=True)))
        self.assertTrue(any(c.startswith(f"release create {TAG}") for c in self.gh_calls()))
        for name in asset_names("x86_64", qcow2=True):
            self.assertEqual(
                (self.release / name).read_bytes(), (self.dist / name).read_bytes()
            )

    def test_raw_only_set_omits_qcow2_assets(self):
        self.stage("x86_64")
        result = self.run_script("publish.sh")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.released(), set(asset_names("x86_64")))

    def test_uncompressed_disks_are_never_uploaded(self):
        self.stage("x86_64", qcow2=True)
        self.assertEqual(self.run_script("publish.sh").returncode, 0)
        self.assertNotIn(raw_name("x86_64"), self.released())
        self.assertNotIn(qcow2_name("x86_64"), self.released())

    def test_architecture_comes_from_the_disk_name(self):
        self.stage("aarch64")
        result = self.run_script("publish.sh")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("podman-vm-aarch64.spdx.json", self.released())

    def test_existing_release_is_not_recreated(self):
        self.publish_existing([])
        self.stage("x86_64")
        result = self.run_script("publish.sh")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertFalse(any(c.startswith("release create") for c in self.gh_calls()))

    def test_complete_set_is_immutable(self):
        self.publish_existing(asset_names("x86_64"))
        self.stage("x86_64")
        result = self.run_script("publish.sh")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("skipping x86_64", result.stdout)
        mutating = [c for c in self.gh_calls() if c.split()[1] in ("upload", "delete-asset")]
        self.assertEqual(mutating, [])
        for name in asset_names("x86_64"):
            self.assertEqual((self.release / name).read_bytes(), b"old\n")

    def test_partial_set_is_deleted_and_republished(self):
        orphans = asset_names("x86_64")[:2]
        self.publish_existing(orphans)
        self.stage("x86_64")
        result = self.run_script("publish.sh")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("PARTIAL x86_64 asset set", result.stderr)
        self.assertEqual(self.released(), set(asset_names("x86_64")))
        for name in orphans:
            self.assertEqual(
                (self.release / name).read_bytes(), (self.dist / name).read_bytes()
            )

    def test_other_architecture_assets_are_left_alone(self):
        other = asset_names("aarch64", qcow2=True)
        self.publish_existing(other)
        self.stage("x86_64")
        result = self.run_script("publish.sh")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.released(), set(other) | set(asset_names("x86_64")))
        for name in other:
            self.assertEqual((self.release / name).read_bytes(), b"old\n")


class PublishRollbackTest(RecipeTestCase):
    def test_upload_failure_rolls_back_every_asset_this_run_uploaded(self):
        names = asset_names("x86_64", qcow2=True)
        for fail_on in names[1:]:
            with self.subTest(fail_on=fail_on):
                shutil.rmtree(self.release, ignore_errors=True)
                self.stage("x86_64", qcow2=True)
                result = self.run_script("publish.sh", self.env(STUB_UPLOAD_FAIL=fail_on))
                self.assertNotEqual(result.returncode, 0)
                self.assertIn("rolling back", result.stderr)
                self.assertEqual(self.released(), set())

    def test_first_upload_failure_fails_without_deleting_anything(self):
        self.stage("x86_64")
        first = asset_names("x86_64")[0]
        result = self.run_script("publish.sh", self.env(STUB_UPLOAD_FAIL=first))
        self.assertNotEqual(result.returncode, 0)
        self.assertFalse(any("delete-asset" in c for c in self.gh_calls()))

    def test_rollback_spares_the_other_architecture(self):
        other = asset_names("aarch64")
        self.publish_existing(other)
        self.stage("x86_64")
        result = self.run_script(
            "publish.sh", self.env(STUB_UPLOAD_FAIL="podman-vm-x86_64.spdx.json")
        )
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(self.released(), set(other))

    def test_size_mismatch_after_upload_rolls_back(self):
        self.stage("x86_64", qcow2=True)
        short = qcow2_name("x86_64") + ".zst"
        result = self.run_script("publish.sh", self.env(STUB_SHORT_UPLOAD=short))
        self.assertNotEqual(result.returncode, 0)
        self.assertIn(f"FAIL: {short} is", result.stderr)
        self.assertIn("rolling back", result.stderr)
        self.assertEqual(self.released(), set())

    def test_repair_then_failure_leaves_no_partial_set(self):
        self.publish_existing(asset_names("x86_64")[:1])
        self.stage("x86_64")
        result = self.run_script(
            "publish.sh", self.env(STUB_UPLOAD_FAIL=asset_names("x86_64")[-1])
        )
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(self.released(), set())


class CompressTest(RecipeTestCase):
    def test_missing_zstd_fails(self):
        (self.bin / "zstd").unlink()
        restricted = self.work / "restricted"
        restricted.mkdir()
        for tool in ("bash", "env", "basename", "sha256sum", "ls"):
            path = shutil.which(tool)
            if path:
                (restricted / tool).symlink_to(path)
        self.stage("x86_64")
        result = self.run_script("compress.sh", self.env(PATH=str(restricted)))
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("zstd not found", result.stderr)

    def test_no_disks_fails(self):
        result = self.run_script("compress.sh")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("no VM disk images in dist-vm/", result.stderr)

    def test_each_disk_gets_a_zst_and_a_checksum_of_the_zst(self):
        for disk in (raw_name("x86_64"), qcow2_name("x86_64")):
            (self.dist / disk).write_bytes(b"disk " + disk.encode())
        result = self.run_script("compress.sh")
        self.assertEqual(result.returncode, 0, result.stderr)
        for disk in (raw_name("x86_64"), qcow2_name("x86_64")):
            zst = self.dist / (disk + ".zst")
            self.assertTrue(zst.is_file())
            self.assertTrue((self.dist / disk).is_file(), "the source disk must be kept")
            line = (self.dist / (disk + ".zst.sha256")).read_text()
            digest = hashlib.sha256(zst.read_bytes()).hexdigest()
            # Relative name, so `sha256sum -c` works after download.
            self.assertEqual(line, f"{digest} *{disk}.zst\n")
        check = subprocess.run(
            ["sha256sum", "-c", raw_name("x86_64") + ".zst.sha256"],
            cwd=self.dist, capture_output=True, text=True,
        )
        self.assertEqual(check.returncode, 0, check.stdout + check.stderr)

    def test_zstd_is_asked_to_keep_the_source_and_overwrite_the_output(self):
        (self.dist / raw_name("x86_64")).write_bytes(b"d")
        self.assertEqual(self.run_script("compress.sh").returncode, 0)
        argv = (self.work / "zstd.log").read_text().split()
        self.assertIn("--keep", argv)
        self.assertIn("--force", argv)

    def test_unrelated_files_are_not_compressed(self):
        (self.dist / raw_name("x86_64")).write_bytes(b"d")
        (self.dist / "notes.raw").write_bytes(b"x")
        (self.dist / "podman-vm-x86_64.spdx.json").write_bytes(b"{}")
        self.assertEqual(self.run_script("compress.sh").returncode, 0)
        self.assertFalse((self.dist / "notes.raw.zst").exists())
        self.assertFalse((self.dist / "podman-vm-x86_64.spdx.json.zst").exists())

    def test_zstd_failure_propagates(self):
        (self.bin / "zstd").write_text("#!/usr/bin/env bash\nexit 1\n")
        (self.dist / raw_name("x86_64")).write_bytes(b"d")
        result = self.run_script("compress.sh")
        self.assertNotEqual(result.returncode, 0)
        self.assertFalse((self.dist / (raw_name("x86_64") + ".zst.sha256")).exists())


if __name__ == "__main__":
    unittest.main()
