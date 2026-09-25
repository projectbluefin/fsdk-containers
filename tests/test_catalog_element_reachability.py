"""Every BuildStream element file must be reachable from a published target.

Roots are the OCI images declared in ``elements/targets.json``, the
``oci/brew-nspawn.bst`` image, the ``podman-vm/podman-vm-efi.bst`` VM guest
element, and the junctions named in ``project.conf``. The walk is static
(regex over ``depends:``/``build-depends:`` filenames) so it runs without a
BuildStream environment — unlike ``just validate``, which needs ``bst``.

Elements that are intentionally inert — fleet-batch spikes tracked in
issues #146/#144, see
``docs/superpowers/specs/2026-08-20-fleet-batch-improvement-design.md`` —
must be declared in SPIKE_ELEMENTS below. The registry is keyed by element
*file*, not by directory, because graduation happens per file: a spike
directory can have its stack wired into a published image while its
runtime chisel stays inert. The registry is asserted in both directions: an
unreachable element not in the registry fails, and a registry entry whose
file no longer exists fails, so a graduated or deleted spike cannot leave a
stale entry behind.

The contributor-facing contract is documented in
``docs/skills/add-new-image.md`` ("Element reachability and the spike
registry").
"""

from pathlib import Path
import json
import re
import unittest

ROOT = Path(__file__).parents[1]
ELEMENTS = ROOT / "elements"

# Intentionally inert spike element files (fleet batch, issue #146; volcano
# and kubestellar-hive gated on #144). Keys are paths relative to
# ``elements/``. A spike file graduating to a real image must be removed
# from this registry in the same PR that wires it into a published target —
# and only that file: ``node/node.bst`` and ``node/node-stack.bst``
# graduated into ``review-runtime`` while ``node/node-runtime.bst``, the
# distroless chisel for a standalone ``oci/node.bst`` that does not exist
# yet, is still inert.
SPIKE_ELEMENTS = {
    "curl/curl-runtime.bst": "#146",
    "curl/curl-stack.bst": "#146",
    "falco/falco-stack.bst": "#146",
    "falco/falco.bst": "#146",
    "go-md2man/go-md2man.bst": "#146",
    "go/go-runtime.bst": "#146",
    "go/go-stack.bst": "#146",
    "kubestellar-hive/hive-bin.bst": "#144",
    "kubestellar-hive/kubestellar-hive-stack.bst": "#144",
    "kubestellar-hive/libwebsockets.bst": "#144",
    "kubestellar-hive/ttyd.bst": "#144",
    "mariadb/mariadb-runtime.bst": "#146",
    "mariadb/mariadb-stack.bst": "#146",
    "mariadb/mariadb.bst": "#146",
    "nginx/nginx-runtime.bst": "#146",
    "nginx/nginx-stack.bst": "#146",
    "nginx/nginx.bst": "#146",
    "node/node-runtime.bst": "#146",
    "postgres/postgres-runtime.bst": "#146",
    "postgres/postgres-stack.bst": "#146",
    "postgres/postgres.bst": "#146",
    "valkey/valkey-runtime.bst": "#146",
    "valkey/valkey-stack.bst": "#146",
    "valkey/valkey.bst": "#146",
    "volcano/volcano-runtime.bst": "#144",
    "volcano/volcano-stack.bst": "#144",
    "volcano/volcano.bst": "#144",
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
    """Walk `depends:` edges from `roots`.

    A root that names no element file is an error, not a silent skip: a
    typo'd or deleted root would otherwise shrink the closure and surface
    as a pile of unrelated orphans.
    """
    missing = sorted(r for r in roots if not (ELEMENTS / r).exists())
    if missing:
        raise FileNotFoundError(
            f"publication roots with no element file under elements/: {missing}"
        )
    seen: set[str] = set()
    stack = list(roots)
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
        # Publication lanes that are not OCI images and so are absent from
        # targets.json: the nspawn machine-image exception documented in
        # AGENTS.md ("One documented exception — machine images") and
        # docs/skills/nspawn-machine-image.md, plus the podman VM guest.
        # A second machine image or VM guest must be added here or every
        # element under it reads as a false orphan.
        roots.add("oci/brew-nspawn.bst")
        roots.add("podman-vm/podman-vm-efi.bst")
        # The printing-base-devel CAS bundle (.github/workflows/printing-base.yml,
        # docs/skills/printing-base.md): a build-time artifact lane, not an image.
        roots.add("printing/base.bst")
        project_conf = (ROOT / "project.conf").read_text(encoding="utf-8")
        roots |= set(JUNCTION_RE.findall(project_conf))
        cls.reachable = dependency_closure(roots)
        cls.elements = all_elements()

    def test_every_element_is_reachable_or_a_declared_spike(self):
        orphans = (self.elements - self.reachable) - set(SPIKE_ELEMENTS)
        self.assertEqual(
            orphans,
            set(),
            "element files unreachable from every published target and not "
            "declared in SPIKE_ELEMENTS — wire them into a target or register "
            "the spike with its tracking issue",
        )

    def test_spike_registry_has_no_stale_entries(self):
        for rel, issue in SPIKE_ELEMENTS.items():
            with self.subTest(spike=rel):
                self.assertTrue(
                    (ELEMENTS / rel).is_file(),
                    f"SPIKE_ELEMENTS entry {rel!r} ({issue}) has no element "
                    "file — remove the registry entry",
                )

    def test_registered_spikes_are_actually_unreachable(self):
        graduated = set(SPIKE_ELEMENTS) & self.reachable
        self.assertEqual(
            graduated,
            set(),
            "these spike elements are now reachable from a published target "
            "— they graduated; remove exactly these entries from "
            "SPIKE_ELEMENTS",
        )


if __name__ == "__main__":
    unittest.main()
