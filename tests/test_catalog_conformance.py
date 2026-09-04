"""Every published image has a record, and every record has an image."""

import json
from pathlib import Path
import sys
import unittest

import yaml

ROOT = Path(__file__).parents[1]
sys.path.insert(0, str(ROOT / "scripts"))

import catalog  # noqa: E402

TARGETS = json.loads((ROOT / "elements" / "targets.json").read_text())


class CatalogCoverageTests(unittest.TestCase):
    def test_every_published_image_has_a_record(self):
        recorded = {r["name"] for r in catalog.load_all()}
        published = set(TARGETS["oci_images"])
        self.assertEqual(
            published - recorded,
            set(),
            "published images with no catalog record",
        )

    def test_every_record_is_a_published_image(self):
        recorded = {r["name"] for r in catalog.load_all()}
        published = set(TARGETS["oci_images"])
        self.assertEqual(
            recorded - published,
            set(),
            "catalog records for images not in targets.json oci_images",
        )

    def test_exactly_one_shell_enabled_image(self):
        shell_enabled = [
            r["name"] for r in catalog.load_all() if r["kind"] == "shell-enabled"
        ]
        self.assertEqual(
            shell_enabled,
            ["lab-runner"],
            "lab-runner is the only documented shell-enabled OCI exception",
        )


class AddingAnImageCostsOneFileTests(unittest.TestCase):
    """The headline success criterion: a new image is one record and nothing
    else. If this test needs editing to add an image, the plan failed."""

    def test_a_new_record_generates_all_three_elements(self):
        import generate_image_elements as gen

        record = {
            "name": "acceptance-probe",
            "kind": "distroless",
            "description": "Throwaway record proving generation needs no code",
            "entrypoint": ["/usr/bin/true"],
            "smoke": {"args": []},
            "size_ceiling_mib": 64,
            "keywords": "probe,acceptance",
            "stack": {
                "depends": [
                    "base/base-stack.bst",
                    "freedesktop-sdk.bst:components/coreutils.bst",
                ],
            },
        }
        catalog.validate(record)

        for renderer in (gen.render_stack, gen.render_compose, gen.render_oci):
            text = renderer(record)
            self.assertIn("DO NOT EDIT", text)
            rendered = yaml.safe_load(text)
            self.assertIsInstance(rendered, dict)

        stack = yaml.safe_load(gen.render_stack(record))
        self.assertEqual(stack["kind"], "stack")
        self.assertEqual(stack["depends"], record["stack"]["depends"])

        compose = yaml.safe_load(gen.render_compose(record))
        self.assertEqual(compose["kind"], "compose")
        self.assertEqual(
            compose["build-depends"],
            ["acceptance-probe/acceptance-probe-stack.bst"],
        )
        self.assertEqual(
            compose["config"]["exclude"],
            catalog.compose_exclude(record),
        )

        oci_text = gen.render_oci(record)
        oci = yaml.safe_load(oci_text)
        self.assertEqual(oci["kind"], "script")
        self.assertEqual(oci["config"]["commands"][0], "%{slim-distroless-commands}")
        self.assertIn("build-oci", oci["config"]["commands"][-1])
        self.assertIn("'io.artifacthub.package.keywords': 'probe,acceptance'", oci_text)
        self.assertIn("'org.opencontainers.image.title': 'acceptance-probe'", oci_text)
        self.assertIn(
            "'org.opencontainers.image.description': "
            "'Throwaway record proving generation needs no code'",
            oci_text,
        )

    def test_generation_depends_only_on_record_not_name(self):
        """Names must not grow per-image branches in the generator."""
        import generate_image_elements as gen

        base = {
            "name": "probe-alpha",
            "kind": "distroless",
            "description": "Throwaway record proving generation needs no code",
            "entrypoint": ["/usr/bin/true"],
            "smoke": {"args": []},
            "size_ceiling_mib": 64,
            "keywords": "probe,acceptance",
            "stack": {
                "depends": [
                    "base/base-stack.bst",
                    "freedesktop-sdk.bst:components/coreutils.bst",
                ],
            },
        }
        a = dict(base, name="python")
        b = dict(base, name="probe-beta")
        for renderer in (gen.render_stack, gen.render_compose, gen.render_oci):
            text_a = renderer(a).replace("python", "NAME")
            text_b = renderer(b).replace("probe-beta", "NAME")
            self.assertEqual(text_a, text_b)


def _element(*parts):
    return yaml.safe_load((ROOT / "elements" / Path(*parts)).read_text())


class RecordsDescribeRealityTests(unittest.TestCase):
    """A record that lies about its elements would silently change an image
    the moment the generator takes ownership. Assert agreement first."""

    def test_stack_depends_match_the_record(self):
        for record in catalog.load_all():
            with self.subTest(image=record["name"]):
                name = record["name"]
                committed = _element(name, f"{name}-stack.bst")
                self.assertEqual(
                    committed["depends"],
                    record["stack"]["depends"],
                    f"{name}-stack.bst depends do not match catalog/{name}.yaml",
                )

    def test_compose_exclude_matches_the_record(self):
        for record in catalog.load_all():
            with self.subTest(image=record["name"]):
                name = record["name"]
                committed = _element(name, f"{name}-runtime.bst")
                self.assertEqual(
                    sorted(committed["config"]["exclude"]),
                    sorted(catalog.compose_exclude(record)),
                    f"{name}-runtime.bst exclude set does not match "
                    f"catalog/{name}.yaml; declare the difference in "
                    f"compose.exclude_omit with a reason",
                )

    def test_slim_extra_matches_the_committed_oci_element(self):
        """Extras are identified STRUCTURALLY, by position, not by substring.

        An earlier draft filtered commands with `"build-oci" not in c`, which a
        slim command merely mentioning that string would satisfy -- letting an
        undeclared extra vanish and the assertion pass vacuously. It also
        compared with .strip() on both sides while claiming byte-equality.

        Every oci element has the same shape, verified across all seven:
            commands[0]   the slim macro
            commands[1:-2] the image's extra slim commands (usually none)
            commands[-2]  the /initial_scripts boilerplate
            commands[-1]  the build-oci heredoc
        """
        for record in catalog.load_all():
            with self.subTest(image=record["name"]):
                name = record["name"]
                committed = _element("oci", f"{name}.bst")
                commands = committed["config"]["commands"]

                # Assert the shape before trusting the slice, so a future
                # element that breaks this layout fails loudly here rather
                # than silently comparing the wrong commands.
                self.assertTrue(
                    commands[0].startswith("%{slim-"),
                    f"oci/{name}.bst: first command is not the slim macro",
                )
                self.assertIn(
                    "initial_scripts", commands[-2],
                    f"oci/{name}.bst: second-to-last command is not the "
                    f"initial_scripts boilerplate",
                )
                self.assertIn(
                    "build-oci", commands[-1],
                    f"oci/{name}.bst: last command is not the build-oci heredoc",
                )

                extras = commands[1:-2]
                declared = record.get("slim", {}).get("extra")
                expected = [] if declared is None else [declared]
                self.assertEqual(
                    extras, expected,
                    f"catalog/{name}.yaml slim.extra is not byte-equal to the "
                    f"extra commands in oci/{name}.bst",
                )


class PathOwnershipTests(unittest.TestCase):
    """`image_paths` is the pull-request build gate's half of the manifest.

    `oci_images` and `image_paths` are two independent structures in
    elements/targets.json that must describe the same set of images. Only
    `oci_images` was cross-checked (against catalog/), so an image could be
    published with no path ownership at all: `just changed-targets` matches a
    changed file against `image_paths` only, and an image absent from it can
    never be selected. That fails open — the image's pull-request build gate
    is silently disabled rather than erroring.

    These tests close the loop: every published image owns paths, every owned
    path set belongs to a published image, and the paths an image owns
    actually cover the four files that define it — its catalog record and the
    three elements scripts/generate_image_elements.py generates from it.
    """

    def _owns(self, image, path):
        """Mirror the prefix/exact matching in the `changed-targets` recipe."""
        for prefix in TARGETS["image_paths"][image]:
            if prefix.endswith("/"):
                if path.startswith(prefix):
                    return True
            elif path == prefix:
                return True
        return False

    def test_every_published_image_owns_paths(self):
        published = set(TARGETS["oci_images"])
        owning = set(TARGETS["image_paths"])
        self.assertEqual(
            published - owning,
            set(),
            "images in oci_images with no image_paths entry: their "
            "pull-request build gate can never select them",
        )

    def test_every_path_owner_is_a_published_image(self):
        published = set(TARGETS["oci_images"])
        owning = set(TARGETS["image_paths"])
        self.assertEqual(
            owning - published,
            set(),
            "image_paths entries for images not in oci_images",
        )

    def test_image_paths_cover_the_files_that_define_the_image(self):
        for name in TARGETS["oci_images"]:
            with self.subTest(image=name):
                for path in (
                    f"catalog/{name}.yaml",
                    f"elements/oci/{name}.bst",
                    f"elements/{name}/{name}-runtime.bst",
                    f"elements/{name}/{name}-stack.bst",
                ):
                    self.assertTrue(
                        self._owns(name, path),
                        f"{name} does not own {path}: a change to it would "
                        f"select no build target",
                    )

    def test_no_image_owns_another_images_paths(self):
        for name in TARGETS["oci_images"]:
            for other in TARGETS["oci_images"]:
                if other == name:
                    continue
                with self.subTest(image=name, other=other):
                    self.assertFalse(
                        self._owns(name, f"catalog/{other}.yaml"),
                        f"{name} claims ownership of catalog/{other}.yaml",
                    )
                    self.assertFalse(
                        self._owns(name, f"elements/oci/{other}.bst"),
                        f"{name} claims ownership of elements/oci/{other}.bst",
                    )

    def test_shared_paths_cover_the_manifest_and_its_consumers(self):
        """A change to the gate's own inputs must still select the canary."""
        shared = set(TARGETS["shared_paths"])
        for path in (
            "elements/targets.json",
            "Justfile",
            "scripts/catalog.py",
            "scripts/generate_image_elements.py",
            "catalog/schema.json",
        ):
            self.assertIn(
                path,
                shared,
                f"{path} defines the build gate but is not a shared path",
            )

    def test_canary_image_is_published(self):
        self.assertIn(
            TARGETS["canary_image"],
            TARGETS["oci_images"],
            "canary_image is not a published image, so a shared-path change "
            "would select a target that cannot be built",
        )


if __name__ == "__main__":
    unittest.main()
