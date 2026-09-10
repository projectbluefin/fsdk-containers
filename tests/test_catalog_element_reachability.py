"""Every BuildStream element file must be reachable from a published target.

Roots are the OCI images declared in ``elements/targets.json``, the
``oci/brew-nspawn.bst`` image, the ``podman-vm/podman-vm-efi.bst`` VM guest
element, and the junctions named in ``project.conf``. The walk is static
(regex over ``depends:``/``build-depends:`` filenames) so it runs without a
BuildStream environment — unlike ``just validate``, which needs ``bst``.

Elements that are intentionally inert — fleet-batch spikes tracked in
issues #146/#144, see
``docs/superpowers/specs/2026-08-20-fleet-batch-improvement-design.md`` —
must be declared in SPIKE_DIRS below. The registry is asserted in both
directions: an unreachable element not in the registry fails, and a registry
entry whose directory no longer exists fails, so a graduated or deleted
spike cannot leave a stale entry behind.
"""

from pathlib import Path
import json
import re
import unittest

ROOT = Path(__file__).parents[1]
ELEMENTS = ROOT / "elements"

# Intentionally inert spike element directories (fleet batch, issue #146;
# volcano and kubestellar-hive gated on #144). A spike graduating to a real
# image must be removed from this registry in the same PR that wires it into
# a published target.
SPIKE_DIRS = {
    "curl": "#146",
    "falco": "#146",
    "go": "#146",
    "go-md2man": "#146",
    "kubestellar-hive": "#144",
    "mariadb": "#146",
    "nginx": "#146",
    "node": "#146",
    "postgres": "#146",
    "valkey": "#146",
    "volcano": "#144",
}

# Matches `- foo/bar.bst` and `- filename: foo/bar.bst` dependency entries.
# Junction-qualified refs (`junction.bst:path/inside.bst`) resolve to the
# junction element itself, which is correct for reachability purposes.
DEP_RE = re.compile(r"(?:filename:\s*|^\s*-\s+)([\w./-]+\.bst)\b", re.M)

# Junctions are referenced from project.conf (`junction: <path>`), not from
# element depends lists.
JUNCTION_RE = re.compile(r"^\s*junction:\s*([\w./-]+\.bst)\s*$", re.M)

# Junction override mappings use a `.bst` path as a YAML key, e.g.
# gnome-build-meta.bst maps `plugins/buildstream-plugins.bst: ...`.
OVERRIDE_KEY_RE = re.compile(r"^\s*([\w./-]+\.bst)\s*:", re.M)


def all_elements() -> set[str]:
    return {
        str(p.relative_to(ELEMENTS))
        for p in ELEMENTS.rglob("*.bst")
    }


def dependency_closure(roots: set[str]) -> set[str]:
    seen: set[str] = set()
    stack = [r for r in roots if (ELEMENTS / r).exists()]
    while stack:
        current = stack.pop()
        if current in seen:
            continue
        seen.add(current)
        text = (ELEMENTS / current).read_text(encoding="utf-8", errors="replace")
        refs = DEP_RE.findall(text) + OVERRIDE_KEY_RE.findall(text)
        for ref in refs:
            if (ELEMENTS / ref).exists() and ref not in seen:
                stack.append(ref)
    return seen


class ElementReachabilityTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        targets = json.loads((ELEMENTS / "targets.json").read_text())
        roots = {f"oci/{name}.bst" for name in targets["oci_images"]}
        roots.add("oci/brew-nspawn.bst")
        roots.add("podman-vm/podman-vm-efi.bst")
        project_conf = (ROOT / "project.conf").read_text(encoding="utf-8")
        roots |= set(JUNCTION_RE.findall(project_conf))
        cls.reachable = dependency_closure(roots)
        cls.elements = all_elements()

    def test_every_element_is_reachable_or_a_declared_spike(self):
        orphans = set()
        for rel in sorted(self.elements - self.reachable):
            top = rel.split("/", 1)[0]
            if top not in SPIKE_DIRS:
                orphans.add(rel)
        self.assertEqual(
            orphans,
            set(),
            "element files unreachable from every published target and not "
            "declared in SPIKE_DIRS — wire them into a target or register "
            "the spike with its tracking issue",
        )

    def test_spike_registry_has_no_stale_entries(self):
        for name, issue in SPIKE_DIRS.items():
            with self.subTest(spike=name):
                self.assertTrue(
                    (ELEMENTS / name).is_dir(),
                    f"SPIKE_DIRS entry {name!r} ({issue}) has no directory — "
                    "remove the registry entry",
                )

    def test_spike_dirs_are_actually_unreachable(self):
        for name in SPIKE_DIRS:
            reachable_in_dir = {
                rel
                for rel in self.reachable
                if rel == name or rel.startswith(name + "/")
            }
            self.assertEqual(
                reachable_in_dir,
                set(),
                f"spike {name!r} is now reachable from a published target — "
                "it graduated; remove it from SPIKE_DIRS",
            )

    def test_roots_exist(self):
        targets = json.loads((ELEMENTS / "targets.json").read_text())
        for name in targets["oci_images"]:
            with self.subTest(root=name):
                self.assertTrue((ELEMENTS / "oci" / f"{name}.bst").exists())


if __name__ == "__main__":
    unittest.main()
