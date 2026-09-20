"""The FSDK provenance in the SBOM has no published-image gate, so ratchet it here.

`just sbom` / `just sboms` embed ``io.projectbluefin.fsdk.version`` and
``io.projectbluefin.fsdk.ref`` into the SPDX ``creationInfo.creators`` (#128),
which is what makes the *signed* SBOM evidence of which FSDK release an image
was carved from. Nothing downstream reads those creators back:
``oci-images.yml`` verifies only that an ``application/vnd.spdx+json`` referrer
exists, and the recipes themselves run exclusively in the push-gated signing
job -- unreachable from pull requests.

So a change that drops the ``--spdx-creator`` lines would ship provenance-free
SBOMs with every pull-request check green. Two gates close that:

* the recipes now assert their own output with ``jq -e`` after generation, so
  the signing job fails instead of publishing, and
* this module asserts the flags and that assertion are still spelled in the
  Justfile, so the drop fails at pull-request time rather than after merge.

It also pins *how* the values reach the container. The recipe body is a
single-quoted ``bash -c`` script inside a ``--privileged podman run``; a Just
``{{...}}`` interpolation there would paste the junction ``ref:`` line of
``elements/freedesktop-sdk.bst`` (rewritten by update automation) straight into
that script, where a quote or ``$(...)`` would escape the quoting. The values
must travel as ``-e`` environment variables instead.
"""

from pathlib import Path
import re
import unittest

ROOT = Path(__file__).parents[1]
JUSTFILE = ROOT / "Justfile"

SBOM_RECIPES = ("sbom", "sboms")
PROVENANCE_KEYS = (
    "io.projectbluefin.fsdk.version",
    "io.projectbluefin.fsdk.ref",
)


def recipe_body(name: str) -> str:
    """Return the indented body of a Justfile recipe, without its header."""
    text = JUSTFILE.read_text(encoding="utf-8")
    start = re.search(rf"^{re.escape(name)}(?: [^\n]*)?:\s*$", text, re.MULTILINE)
    assert start, f"recipe '{name}' not found in {JUSTFILE}"
    lines = text[start.end() :].splitlines()
    body = []
    for line in lines:
        if line.strip() and not line.startswith((" ", "\t")):
            break
        body.append(line)
    return "\n".join(body)


class SbomProvenanceTests(unittest.TestCase):
    def test_recipes_embed_fsdk_provenance_as_spdx_creators(self):
        for recipe in SBOM_RECIPES:
            body = recipe_body(recipe)
            for key in PROVENANCE_KEYS:
                with self.subTest(recipe=recipe, key=key):
                    self.assertIn(
                        f'--spdx-creator "Organization: {key}=',
                        body,
                        f"`just {recipe}` no longer records {key} in the SBOM",
                    )

    def test_recipes_verify_their_own_output(self):
        """A generated SBOM missing the creators must fail the generating job."""
        for recipe in SBOM_RECIPES:
            body = recipe_body(recipe)
            with self.subTest(recipe=recipe):
                self.assertIn(
                    "jq -e --arg v",
                    body,
                    f"`just {recipe}` does not assert its own creationInfo.creators",
                )
                self.assertIn(".creationInfo.creators", body)

    def test_fsdk_values_reach_the_container_as_env_not_interpolation(self):
        """Justfile:{{fsdk_ref}} inside the privileged `bash -c '...'` would be
        an injection point from an automation-rewritten junction ref."""
        for recipe in SBOM_RECIPES:
            body = recipe_body(recipe)
            script = body.split("bash -c '", 1)
            self.assertEqual(len(script), 2, f"`just {recipe}` lost its bash -c script")
            podman_args, container_script = script
            with self.subTest(recipe=recipe):
                self.assertIn('-e FSDK_VERSION="${fsdk_version}"', podman_args)
                self.assertIn('-e FSDK_REF="${fsdk_ref}"', podman_args)
                self.assertNotIn("{{fsdk_version}}", container_script)
                self.assertNotIn("{{fsdk_ref}}", container_script)
                self.assertIn("${FSDK_VERSION}", container_script)
                self.assertIn("${FSDK_REF}", container_script)


if __name__ == "__main__":
    unittest.main()
