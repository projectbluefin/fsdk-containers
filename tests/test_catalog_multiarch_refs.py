"""Unit and regression tests for multi-arch source ref parity."""

from pathlib import Path
import unittest

import sys
sys.path.insert(0, str(Path(__file__).parents[1] / "scripts"))

from check_multiarch_refs import check_parity, extract_arch_refs


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


if __name__ == "__main__":
    unittest.main()
