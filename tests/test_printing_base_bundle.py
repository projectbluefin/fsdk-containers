"""scripts/printing_base_bundle.py lists exactly the cache files the bundle needs.

The script decides what goes into ghcr.io/<owner>/printing-base-devel: which
elements are bundled (those with a build log for their key), which artifact
refs ship, and which CAS objects BuildStream needs to call each artifact
cached. A mistake does not fail the publish job. It ships a bundle consumers
silently cannot use, and they rebuild the patched CUPS stack from source.

The script imports BuildStream's generated protos, which only exist inside
the bst2 container. These tests replace the two proto modules with minimal
JSON-backed stand-ins exposing the same fields the script reads, so the
selection, CAS walk, de-duplication, ordering and every error exit run on the
host in milliseconds.
"""

import contextlib
import importlib.util
import io
import json
from pathlib import Path
import sys
import tempfile
import types
import unittest


ROOT = Path(__file__).parents[1]
SCRIPT = ROOT / "scripts" / "printing_base_bundle.py"


class Digest:
    def __init__(self, hash="", size_bytes=0):
        self.hash = hash
        self.size_bytes = size_bytes

    def __str__(self):
        # Mirrors protobuf: an unset message prints as the empty string.
        return f'hash: "{self.hash}"' if self.hash else ""


def _digest(value):
    return Digest(value or "")


class Directory:
    def __init__(self):
        self.files = []
        self.directories = []

    def ParseFromString(self, data):
        doc = json.loads(data)
        self.files = [types.SimpleNamespace(digest=_digest(h)) for h in doc.get("files", [])]
        self.directories = [
            types.SimpleNamespace(digest=_digest(h)) for h in doc.get("directories", [])
        ]


class Artifact:
    def __init__(self):
        self.strong_key = ""
        self.weak_key = ""
        self.files = Digest()
        self.low_diversity_meta = Digest()
        self.high_diversity_meta = Digest()
        self.public_data = Digest()
        self.logs = []

    def ParseFromString(self, data):
        doc = json.loads(data)
        self.strong_key = doc.get("strong_key", "")
        self.weak_key = doc.get("weak_key", "")
        self.files = _digest(doc.get("files"))
        self.low_diversity_meta = _digest(doc.get("low_diversity_meta"))
        self.high_diversity_meta = _digest(doc.get("high_diversity_meta"))
        self.public_data = _digest(doc.get("public_data"))
        self.logs = [types.SimpleNamespace(digest=_digest(h)) for h in doc.get("logs", [])]


def _load_script():
    remote_execution_pb2 = types.ModuleType("remote_execution_pb2")
    remote_execution_pb2.Directory = Directory
    artifact_pb2 = types.ModuleType("artifact_pb2")
    artifact_pb2.Artifact = Artifact
    stubs = {
        "buildstream": types.ModuleType("buildstream"),
        "buildstream._protos": types.ModuleType("buildstream._protos"),
        "buildstream._protos.build": types.ModuleType("buildstream._protos.build"),
        "buildstream._protos.build.bazel": types.ModuleType("buildstream._protos.build.bazel"),
        "buildstream._protos.build.bazel.remote": types.ModuleType("r"),
        "buildstream._protos.build.bazel.remote.execution": types.ModuleType("e"),
        "buildstream._protos.build.bazel.remote.execution.v2": types.ModuleType("v2"),
        "buildstream._protos.build.bazel.remote.execution.v2.remote_execution_pb2": remote_execution_pb2,
        "buildstream._protos.buildstream": types.ModuleType("bs"),
        "buildstream._protos.buildstream.v2": types.ModuleType("bsv2"),
        "buildstream._protos.buildstream.v2.artifact_pb2": artifact_pb2,
    }
    stubs["buildstream._protos.build.bazel.remote.execution.v2"].remote_execution_pb2 = remote_execution_pb2
    stubs["buildstream._protos.buildstream.v2"].artifact_pb2 = artifact_pb2
    saved = {name: sys.modules.get(name) for name in stubs}
    sys.modules.update(stubs)
    try:
        spec = importlib.util.spec_from_file_location("printing_base_bundle", SCRIPT)
        module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(module)
    finally:
        for name, previous in saved.items():
            if previous is None:
                sys.modules.pop(name, None)
            else:
                sys.modules[name] = previous
    return module


bundle = _load_script()

KEY_A = "a" * 64
KEY_B = "b" * 64
WEAK_A = "c" * 64


class Cache:
    """A synthetic BuildStream local cache laid out like the real one."""

    def __init__(self, root):
        self.root = Path(root)

    def obj(self, hash, content=b"x"):
        path = self.root / "cas" / "objects" / hash[:2] / hash[2:]
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(content)
        return hash

    def directory(self, hash, files=(), directories=()):
        return self.obj(
            hash, json.dumps({"files": list(files), "directories": list(directories)}).encode()
        )

    def build_log(self, name, key, project="fsdk"):
        path = self.root / "logs" / project / name / f"{key[:8]}-build.12345.log"
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text("log\n")

    def artifact(self, name, key, project="fsdk", **fields):
        path = self.root / "artifacts" / "refs" / project / name / key
        path.parent.mkdir(parents=True, exist_ok=True)
        fields.setdefault("strong_key", key)
        # BuildStream always records both keys; they coincide unless the
        # element's weak key differs.
        fields.setdefault("weak_key", key)
        path.write_text(json.dumps(fields))
        return path

    def weak_ref(self, name, weak_key, project="fsdk"):
        path = self.root / "artifacts" / "refs" / project / name / weak_key
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text("{}")


def h(n):
    """A distinct fake 64-hex digest."""
    return f"{n:064x}"


class BundleTestCase(unittest.TestCase):
    def setUp(self):
        self._tmp = tempfile.TemporaryDirectory()
        self.cache = Cache(self._tmp.name)

    def tearDown(self):
        self._tmp.cleanup()

    def run_main(self, closure_lines):
        stdout, stderr = io.StringIO(), io.StringIO()
        with contextlib.redirect_stdout(stdout), contextlib.redirect_stderr(stderr):
            bundle.main(str(self.cache.root), [f"{line}\n" for line in closure_lines])
        return stdout.getvalue().splitlines(), stderr.getvalue()

    def assert_exits(self, closure_lines, message):
        with self.assertRaises(SystemExit) as raised, contextlib.redirect_stdout(io.StringIO()):
            bundle.main(str(self.cache.root), [f"{line}\n" for line in closure_lines])
        self.assertIn(message, str(raised.exception))


class TestNormalName(unittest.TestCase):
    def test_path_separators_become_dashes_and_suffix_is_dropped(self):
        self.assertEqual(bundle.normal_name("components/cups.bst"), "components-cups")

    def test_junction_prefix_is_dropped(self):
        self.assertEqual(
            bundle.normal_name("freedesktop-sdk.bst:components/cups-filters.bst"),
            "components-cups-filters",
        )


class TestElementSelection(BundleTestCase):
    def test_only_elements_with_a_build_log_for_their_key_are_bundled(self):
        self.cache.build_log("printing-cups", KEY_A)
        self.cache.artifact("printing-cups", KEY_A)
        # Pulled, not built: an artifact ref but no build log.
        self.cache.artifact("components-zlib", KEY_B)

        paths, stderr = self.run_main(
            [f"printing/cups.bst@@{KEY_A}", f"components/zlib.bst@@{KEY_B}"]
        )

        self.assertIn("bundled: printing/cups.bst", stderr)
        self.assertNotIn("components/zlib.bst", stderr)
        self.assertEqual(paths, [f"artifacts/refs/fsdk/printing-cups/{KEY_A}"])

    def test_build_log_for_a_different_key_does_not_count(self):
        self.cache.build_log("printing-cups", KEY_B)
        self.cache.artifact("printing-cups", KEY_A)
        self.assert_exits([f"printing/cups.bst@@{KEY_A}"], "no element in the closure was built")

    def test_empty_bundle_is_an_error(self):
        self.assert_exits([f"printing/cups.bst@@{KEY_A}"], "no element in the closure was built")

    def test_built_element_without_an_artifact_ref_is_an_error(self):
        self.cache.build_log("printing-cups", KEY_A)
        self.assert_exits(
            [f"printing/cups.bst@@{KEY_A}"],
            f"printing/cups.bst was built but has 0 artifact refs for {KEY_A}",
        )

    def test_built_element_with_refs_in_two_projects_is_an_error(self):
        self.cache.build_log("printing-cups", KEY_A)
        self.cache.artifact("printing-cups", KEY_A, project="one")
        self.cache.artifact("printing-cups", KEY_A, project="two")
        self.assert_exits([f"printing/cups.bst@@{KEY_A}"], "has 2 artifact refs")


class TestRefs(BundleTestCase):
    def test_strong_and_weak_refs_are_both_listed(self):
        self.cache.build_log("printing-cups", KEY_A)
        self.cache.artifact("printing-cups", KEY_A, weak_key=WEAK_A)
        self.cache.weak_ref("printing-cups", WEAK_A)

        paths, _ = self.run_main([f"printing/cups.bst@@{KEY_A}"])

        self.assertEqual(
            sorted(paths),
            sorted(
                [
                    f"artifacts/refs/fsdk/printing-cups/{KEY_A}",
                    f"artifacts/refs/fsdk/printing-cups/{WEAK_A}",
                ]
            ),
        )

    def test_weak_ref_absent_from_the_cache_is_skipped(self):
        self.cache.build_log("printing-cups", KEY_A)
        self.cache.artifact("printing-cups", KEY_A, weak_key=WEAK_A)

        paths, _ = self.run_main([f"printing/cups.bst@@{KEY_A}"])

        self.assertEqual(paths, [f"artifacts/refs/fsdk/printing-cups/{KEY_A}"])

    def test_weak_key_equal_to_strong_key_is_listed_once(self):
        self.cache.build_log("printing-cups", KEY_A)
        self.cache.artifact("printing-cups", KEY_A, weak_key=KEY_A)

        paths, _ = self.run_main([f"printing/cups.bst@@{KEY_A}"])

        self.assertEqual(paths, [f"artifacts/refs/fsdk/printing-cups/{KEY_A}"])


class TestCasWalk(BundleTestCase):
    def objects(self, paths):
        return [p for p in paths if p.startswith("cas/")]

    def test_files_tree_metadata_public_data_and_logs_are_collected(self):
        file1, file2 = self.cache.obj(h(1)), self.cache.obj(h(2))
        subdir = self.cache.directory(h(3), files=[file2])
        root = self.cache.directory(h(4), files=[file1], directories=[subdir])
        meta_low, meta_high, public, log = (self.cache.obj(h(n)) for n in (5, 6, 7, 8))
        self.cache.build_log("printing-cups", KEY_A)
        self.cache.artifact(
            "printing-cups",
            KEY_A,
            files=root,
            low_diversity_meta=meta_low,
            high_diversity_meta=meta_high,
            public_data=public,
            logs=[log],
        )

        paths, stderr = self.run_main([f"printing/cups.bst@@{KEY_A}"])

        expected = sorted(f"cas/objects/{d[:2]}/{d[2:]}" for d in (h(n) for n in range(1, 9)))
        self.assertEqual(self.objects(paths), expected)
        self.assertIn("bundled 1 elements, 1 refs, 8 objects", stderr)

    def test_refs_precede_sorted_objects_for_tar(self):
        self.cache.obj(h(9))
        self.cache.obj(h(1))
        self.cache.build_log("printing-cups", KEY_A)
        self.cache.artifact("printing-cups", KEY_A, public_data=h(9), logs=[h(1)])

        paths, _ = self.run_main([f"printing/cups.bst@@{KEY_A}"])

        self.assertTrue(paths[0].startswith("artifacts/refs/"), paths)
        self.assertEqual(paths[1:], sorted(paths[1:]))

    def test_objects_shared_between_elements_are_listed_once(self):
        shared = self.cache.obj(h(1))
        tree_a = self.cache.directory(h(2), files=[shared])
        tree_b = self.cache.directory(h(3), files=[shared])
        self.cache.build_log("printing-cups", KEY_A)
        self.cache.artifact("printing-cups", KEY_A, files=tree_a)
        self.cache.build_log("printing-ghostscript", KEY_B)
        self.cache.artifact("printing-ghostscript", KEY_B, files=tree_b)

        paths, stderr = self.run_main(
            [f"printing/cups.bst@@{KEY_A}", f"printing/ghostscript.bst@@{KEY_B}"]
        )

        objects = self.objects(paths)
        self.assertEqual(len(objects), len(set(objects)))
        self.assertEqual(len(objects), 3)
        self.assertIn("bundled 2 elements, 2 refs, 3 objects", stderr)

    def test_unset_digests_are_ignored(self):
        """No files tree and no metadata: only the ref ships, nothing errors."""
        self.cache.build_log("printing-cups", KEY_A)
        self.cache.artifact("printing-cups", KEY_A)

        paths, _ = self.run_main([f"printing/cups.bst@@{KEY_A}"])

        self.assertEqual(self.objects(paths), [])

    def test_missing_file_object_is_an_error(self):
        root = self.cache.directory(h(4), files=[h(1)])
        self.cache.build_log("printing-cups", KEY_A)
        self.cache.artifact("printing-cups", KEY_A, files=root)
        self.assert_exits([f"printing/cups.bst@@{KEY_A}"], f"CAS object {h(1)} is missing")

    def test_missing_subdirectory_object_is_an_error(self):
        root = self.cache.directory(h(4), directories=[h(3)])
        self.cache.build_log("printing-cups", KEY_A)
        self.cache.artifact("printing-cups", KEY_A, files=root)
        self.assert_exits([f"printing/cups.bst@@{KEY_A}"], f"CAS object {h(3)} is missing")

    def test_missing_log_object_is_an_error(self):
        self.cache.build_log("printing-cups", KEY_A)
        self.cache.artifact("printing-cups", KEY_A, logs=[h(8)])
        self.assert_exits([f"printing/cups.bst@@{KEY_A}"], f"CAS object {h(8)} is missing")


if __name__ == "__main__":
    unittest.main()
