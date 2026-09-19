"""Unit and regression tests for multi-arch source ref parity."""

from pathlib import Path
import re
import unittest
import urllib.error
import urllib.request
from unittest import mock

import sys
sys.path.insert(0, str(Path(__file__).parents[1] / "scripts"))

from check_multiarch_refs import check_parity, extract_arch_refs


def _http_status_is_transient(code: int) -> bool:
    """Is an upstream HTTP status transport weather rather than a finding?

    ``dl.k8s.io`` is a CDN redirector, so a 5xx or a 429 says nothing about
    this repository and must not fail CI on an unrelated ``elements/**`` edit.
    Every other 4xx -- a 404 above all -- means the version declared in
    ``kubectl.bst`` has no such artifact upstream, which is precisely the
    drift this gate exists to catch.
    """
    return code == 429 or code >= 500


SAMPLE_BST_BEFORE = """kind: manual
variables:
  tool_version: v1.0.0

sources:
- kind: remote
  (?):
  - arch == "x86_64":
      url: "https://example.com/tool-%{tool_version}-x86_64.tar.gz"
      ref: 1111111111111111111111111111111111111111111111111111111111111111
  - arch == "aarch64":
      url: "https://example.com/tool-%{tool_version}-aarch64.tar.gz"
      ref: 2222222222222222222222222222222222222222222222222222222222222222
  filename: tool.tar.gz
"""

SAMPLE_BST_X86_ONLY = """kind: manual
variables:
  tool_version: v1.0.1

sources:
- kind: remote
  (?):
  - arch == "x86_64":
      url: "https://example.com/tool-%{tool_version}-x86_64.tar.gz"
      ref: 3333333333333333333333333333333333333333333333333333333333333333
  - arch == "aarch64":
      url: "https://example.com/tool-%{tool_version}-aarch64.tar.gz"
      ref: 2222222222222222222222222222222222222222222222222222222222222222
  filename: tool.tar.gz
"""

SAMPLE_BST_BOTH_BUMPED = """kind: manual
variables:
  tool_version: v1.0.1

sources:
- kind: remote
  (?):
  - arch == "x86_64":
      url: "https://example.com/tool-%{tool_version}-x86_64.tar.gz"
      ref: 3333333333333333333333333333333333333333333333333333333333333333
  - arch == "aarch64":
      url: "https://example.com/tool-%{tool_version}-aarch64.tar.gz"
      ref: 4444444444444444444444444444444444444444444444444444444444444444
  filename: tool.tar.gz
"""

SAMPLE_BST_VERSION_ONLY = """kind: manual
variables:
  tool_version: v1.0.1

sources:
- kind: remote
  (?):
  - arch == "x86_64":
      url: "https://example.com/tool-%{tool_version}-x86_64.tar.gz"
      ref: 1111111111111111111111111111111111111111111111111111111111111111
  - arch == "aarch64":
      url: "https://example.com/tool-%{tool_version}-aarch64.tar.gz"
      ref: 2222222222222222222222222222222222222222222222222222222222222222
  filename: tool.tar.gz
"""


class MultiarchRefParityTests(unittest.TestCase):
    def test_extract_arch_refs(self):
        refs = extract_arch_refs(SAMPLE_BST_BEFORE)
        self.assertEqual(
            refs,
            {
                "x86_64": "1" * 64,
                "aarch64": "2" * 64,
            },
        )

    def test_detects_x86_only_ref_bump(self):
        err = check_parity("elements/tool.bst", SAMPLE_BST_BEFORE, SAMPLE_BST_X86_ONLY)
        self.assertIsNotNone(err)
        self.assertIn("asymmetric multi-arch ref update", err)
        self.assertIn("x86_64 changed=True", err)
        self.assertIn("aarch64 changed=False", err)

    def test_accepts_symmetric_ref_bump(self):
        err = check_parity("elements/tool.bst", SAMPLE_BST_BEFORE, SAMPLE_BST_BOTH_BUMPED)
        self.assertIsNone(err)

    def test_accepts_version_only_bump(self):
        err = check_parity("elements/tool.bst", SAMPLE_BST_BEFORE, SAMPLE_BST_VERSION_ONLY)
        self.assertIsNone(err)

    def test_all_committed_multiarch_elements_have_valid_refs(self):
        root = Path(__file__).parents[1]
        for bst in sorted((root / "elements").rglob("*.bst")):
            content = bst.read_text(encoding="utf-8")
            refs = extract_arch_refs(content)
            if refs:
                self.assertIn("x86_64", refs, f"{bst} defines arch refs but missing x86_64")
                self.assertIn("aarch64", refs, f"{bst} defines arch refs but missing aarch64")
                for arch, ref in refs.items():
                    self.assertTrue(ref, f"{bst} {arch} ref is empty")

    def test_ignores_arch_conditionals_outside_sources(self):
        # A (?) block under `variables:` (e.g. per-arch hardening-flags) is
        # not a source ref and must not be picked up.
        bst = """kind: manual
variables:
  hardening-flags: ""
  (?):
  - arch == "x86_64":
      hardening-flags: "-fstack-protector-strong"
  - arch == "aarch64":
      hardening-flags: "-mbranch-protection=standard"
"""
        self.assertEqual(extract_arch_refs(bst), {})

    def test_extracts_git_repo_describe_form_refs(self):
        # git_repo refs are BuildStream describe-form strings, not bare
        # digests -- the old line-scanning regex only matched hex, so it
        # returned {} for these and silently skipped the parity check.
        bst = """kind: manual
sources:
- kind: git_repo
  (?):
  - arch == "x86_64":
      url: "github:example/tool.git"
      ref: v1.0.0-0-gdb97cce32cecadc7a3e98f06d557ebfa6ba9ad46
  - arch == "aarch64":
      url: "github:example/tool.git"
      ref: v1.0.0-0-g7ae7d5a4021b24d02a5c281badca8c4d8ebbf442
"""
        self.assertEqual(
            extract_arch_refs(bst),
            {
                "x86_64": "v1.0.0-0-gdb97cce32cecadc7a3e98f06d557ebfa6ba9ad46",
                "aarch64": "v1.0.0-0-g7ae7d5a4021b24d02a5c281badca8c4d8ebbf442",
            },
        )

    def test_extracts_single_quoted_and_uncommon_arches(self):
        # The old regex hardcoded a `(x86_64|aarch64)` alternation and only
        # matched double quotes -- elements/freedesktop-sdk.bst uses single
        # quotes and also conditions on ppc64le/riscv64.
        bst = """kind: manual
sources:
- kind: remote
  (?):
  - arch == 'x86_64':
      url: "https://example.com/tool-x86_64.tar.gz"
      ref: 1111111111111111111111111111111111111111111111111111111111111111
  - arch == 'ppc64le':
      url: "https://example.com/tool-ppc64le.tar.gz"
      ref: 2222222222222222222222222222222222222222222222222222222222222222
  - arch == 'riscv64':
      url: "https://example.com/tool-riscv64.tar.gz"
      ref: 3333333333333333333333333333333333333333333333333333333333333333
  filename: tool.tar.gz
"""
        self.assertEqual(
            extract_arch_refs(bst),
            {
                "x86_64": "1" * 64,
                "ppc64le": "2" * 64,
                "riscv64": "3" * 64,
            },
        )

    def test_detects_asymmetric_update_among_three_arches(self):
        # check_parity used to hardcode the x86_64/aarch64 pair; an element
        # conditioning a third arch's ref got no parity enforcement at all.
        before = """kind: manual
sources:
- kind: remote
  (?):
  - arch == "x86_64":
      ref: 1111111111111111111111111111111111111111111111111111111111111111
  - arch == "aarch64":
      ref: 2222222222222222222222222222222222222222222222222222222222222222
  - arch == "ppc64le":
      ref: 3333333333333333333333333333333333333333333333333333333333333333
"""
        after = """kind: manual
sources:
- kind: remote
  (?):
  - arch == "x86_64":
      ref: 4444444444444444444444444444444444444444444444444444444444444444
  - arch == "aarch64":
      ref: 2222222222222222222222222222222222222222222222222222222222222222
  - arch == "ppc64le":
      ref: 3333333333333333333333333333333333333333333333333333333333333333
"""
        err = check_parity("elements/tool.bst", before, after)
        self.assertIsNotNone(err)
        self.assertIn("x86_64 changed=True", err)
        self.assertIn("aarch64 changed=False", err)
        self.assertIn("ppc64le changed=False", err)

    def test_kubectl_multiarch_refs_match_upstream(self):
        # Issue #215 / PR #213 regression test: ensure kubectl element has matching multi-arch refs
        # and version-agnostic alignment with upstream release checksums when online.
        root = Path(__file__).parents[1]
        kubectl_bst = root / "elements" / "lab-runner" / "kubectl.bst"
        content = kubectl_bst.read_text(encoding="utf-8")
        refs = extract_arch_refs(content)
        self.assertIn("x86_64", refs)
        self.assertIn("aarch64", refs)

        match = re.search(r"^\s*kubectl_version:\s*(\S+)\s*$", content, re.MULTILINE)
        self.assertIsNotNone(match, "kubectl_version variable not found in kubectl.bst")
        version = match.group(1).strip()

        arch_map = {"x86_64": "amd64", "aarch64": "arm64"}
        verified_count = 0
        for arch, k8s_arch in arch_map.items():
            url = f"https://dl.k8s.io/release/{version}/bin/linux/{k8s_arch}/kubectl.sha256"
            try:
                req = urllib.request.Request(url, headers={"User-Agent": "fsdk-test"})
                with urllib.request.urlopen(req, timeout=5) as resp:
                    expected_hash = resp.read().decode("utf-8").strip()
                    self.assertEqual(
                        refs[arch],
                        expected_hash,
                        f"kubectl ref for {arch} ({refs[arch]}) does not match upstream {version} {k8s_arch} hash ({expected_hash})",
                    )
                    verified_count += 1
            except urllib.error.HTTPError as exc:
                if _http_status_is_transient(exc.code):
                    self.skipTest(
                        f"upstream returned HTTP {exc.code} for {url}: {exc}"
                    )
                self.fail(
                    f"Upstream release checksum fetch failed with HTTP {exc.code} "
                    f"for {version} ({url}): {exc}"
                )
            except (urllib.error.URLError, TimeoutError, OSError) as exc:
                self.skipTest(f"upstream unreachable for {url}: {exc}")

        self.assertEqual(
            verified_count,
            len(arch_map),
            f"Expected {len(arch_map)} verified architectures, verified {verified_count}",
        )

    def test_upstream_404_fails_while_throttling_and_5xx_skip(self):
        # Drive the gate itself, not the predicate: HTTPError subclasses
        # URLError subclasses OSError, so reordering the two except clauses
        # silently restores the #215 hole -- a 404 on a declared version is
        # swallowed as "offline" and the gate reports success. 429 is the
        # precedence trap: a 4xx that must still skip.
        def _raise(code):
            def _urlopen(*_args, **_kwargs):
                raise urllib.error.HTTPError(
                    "https://dl.k8s.io/", code, "synthetic", {}, None
                )

            return _urlopen

        with mock.patch.object(urllib.request, "urlopen", _raise(404)):
            try:
                self.test_kubectl_multiarch_refs_match_upstream()
            except self.failureException:
                pass
            except unittest.SkipTest:
                self.fail("HTTP 404 on the declared version was swallowed as a skip")
            else:
                self.fail("HTTP 404 on the declared version did not fail the gate")

        for transient in (429, 503):
            with mock.patch.object(urllib.request, "urlopen", _raise(transient)):
                with self.assertRaises(unittest.SkipTest):
                    self.test_kubectl_multiarch_refs_match_upstream()


if __name__ == "__main__":
    unittest.main()
