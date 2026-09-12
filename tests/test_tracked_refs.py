"""Release-tracked git sources must pin the commit their `track:` tag names.

#234: buildah tracked v1.45.0 while its `ref:` still pinned the v1.44.1
commit. Unlike a stale tarball sha256, a stale git commit ref fetches fine and
silently builds the older source; the drift surfaced only when FSDK 26.08.0's
Go 1.27 could no longer compile that older source's vendored grpc/x/net pair
(`undefined: http2.TrailerPrefix`). `just validate` cannot catch this — it
resolves the element graph, not the upstream tag — so check the pin against
the live tag here.

Scope is the published OCI image lanes from elements/targets.json (the lanes
the oci-images workflow builds). Junction tracks with globs
(`freedesktop-sdk-26.08*`), branch tracks (`gnome-50`, `v2`), and untracked
pins name no single release tag, so there is nothing to verify against.
"""

import json
from pathlib import Path
import re
import subprocess
import unittest


ROOT = Path(__file__).parents[1]

ALIASES = {
    "github:": "https://github.com/",
    "gitlab:": "https://gitlab.com/",
    "gnome:": "https://gitlab.gnome.org/GNOME/",
}

EXACT_TAG = re.compile(r"^v?\d+\.\d+\.\d+$")
DESCRIBE = re.compile(r"^(?P<tag>.+)-0-g(?P<sha>[0-9a-f]{40})$")
PLAIN_SHA = re.compile(r"^[0-9a-f]{40}$")


def _oci_element_files():
    targets = json.loads((ROOT / "elements" / "targets.json").read_text())
    files = []
    for paths in targets["image_paths"].values():
        for entry in paths:
            path = ROOT / entry
            if entry.endswith("/"):
                files.extend(sorted(path.rglob("*.bst")))
            elif path.suffix == ".bst":
                files.append(path)
    return files


def _git_repo_sources(path):
    text = path.read_text()
    for block in re.split(r"\n\s*-\s+kind:\s*", text)[1:]:
        if not block.startswith("git_repo"):
            continue
        fields = {}
        for key in ("url", "track", "ref"):
            match = re.search(rf"^\s+{key}:\s*\"?([^\s\"]+)\"?", block, re.M)
            if match:
                fields[key] = match.group(1)
        yield fields


def _resolve_alias(url):
    for alias, base in ALIASES.items():
        if url.startswith(alias):
            return base + url[len(alias):]
    return url


def _tag_commit(url, tag):
    for ref in (f"refs/tags/{tag}^{{}}", f"refs/tags/{tag}"):
        try:
            out = subprocess.run(
                ["git", "ls-remote", url, ref],
                capture_output=True, text=True, timeout=60, check=True,
            ).stdout.split()
        except (subprocess.CalledProcessError, subprocess.TimeoutExpired) as exc:
            raise unittest.SkipTest(f"git ls-remote {url} unavailable: {exc}")
        if out:
            return out[0]
    return None


class TrackedGitRefTests(unittest.TestCase):
    def test_exact_tag_tracks_pin_the_tagged_commit(self):
        checked = 0
        for path in _oci_element_files():
            for source in _git_repo_sources(path):
                track = source.get("track", "")
                ref = source.get("ref", "")
                if not EXACT_TAG.match(track) or not ref:
                    continue
                checked += 1
                with self.subTest(element=path.relative_to(ROOT), track=track):
                    pinned = DESCRIBE.match(ref)
                    sha = pinned.group("sha") if pinned else ref
                    if pinned:
                        self.assertEqual(
                            pinned.group("tag"), track,
                            "describe-format ref names a different tag than track:",
                        )
                    elif not PLAIN_SHA.match(ref):
                        self.fail(f"unrecognised ref format: {ref}")
                    tagged = _tag_commit(_resolve_alias(source["url"]), track)
                    self.assertIsNotNone(tagged, f"no such upstream tag: {track}")
                    self.assertEqual(
                        sha, tagged,
                        f"track: {track} but ref pins a different commit",
                    )
        self.assertGreater(
            checked, 0, "no exact-tag git_repo sources found — check the parser"
        )


if __name__ == "__main__":
    unittest.main()
