# Image Catalog Generation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make adding a container image cost one declarative record instead of four hand-authored artifacts.

**Architecture:** Every OCI image gets one YAML record in `catalog/`. A generator script emits the three BuildStream elements (`stack`, `compose`, `script`) from that record, and `just verify` derives its gates and smoke test from it. A `--check` mode gates CI against drift, following the existing `scripts/generate_skill_index.py` pattern exactly. Migration is proven safe by asserting semantic equality between generated and committed elements *before* the generator takes ownership.

**Tech Stack:** Python 3 (stdlib + `PyYAML` + `jsonschema`, all already used by `scripts/generate_skill_index.py`), `unittest` for tests, BuildStream 2 elements, `just` recipes, GitHub Actions.

## Global Constraints

- Compose from FSDK `components/*`, never `platform.bst`.
- No `x86_64_v3`. Do not add a micro-architecture option.
- Distroless means no shell. `lab-runner` is the only OCI exception, and `brew` is a non-OCI nspawn machine image outside this plan's scope.
- `just verify` is the merge contract. Every gate that passes today must still pass after every task.
- The canonical compose exclude set is exactly: `debug`, `devel`, `doc`, `locale`, `shells`, `static-blocklist`, `tests`, `vm-only`.
- Python tests use `unittest`, not `pytest`, matching `tests/test_renovate_atomic.py`. **Always invoke via discovery** — `python3 -m unittest discover -s tests -p '<file>.py' -v` — never `python3 -m unittest tests.<module>`. A `tests` package installed in user site-packages shadows this repo's `tests/` directory, so the dotted form silently runs the wrong code. Select a single test with `-k <name>`.
- Generated files are committed to git and gated by a `--check` mode. Never generate at build time.
- Commit messages follow Conventional Commits with a scope, and end with:
  `Co-authored-by: Copilot <223556219+Copilot@users.noreply.github.com>`
- Look tools up via Context7 before use, per `AGENTS.md`.
- This plan makes **no behavioural change to any published image**. Any task that produces a different image is a failed task.

---

## Why this plan exists

Adding an image today requires hand-authoring four things: component selection, a bespoke slim list, a per-image entry in the `Justfile`'s verify case statement, and metadata. Only component selection needs human judgement.

The evidence that the rest is boilerplate, measured 2026-08-21 across all 16 `*-runtime.bst` compose elements:

- **13 of 16 have byte-identical exclude sets.**
- The 3 that differ are `brew` (legitimately — nspawn, out of scope), `go` (missing `devel`), and `lab-runner` (missing `shells`). Neither deviation is documented anywhere.

Generation converts silent divergence into declared, reviewed divergence. That is the point of Task 3.

## File Structure

| File | Responsibility |
| --- | --- |
| `catalog/schema.json` | JSON Schema 2020-12 for one image record. The contract. |
| `catalog/<name>.yaml` | One record per OCI image. **The only file a human writes to add an image.** |
| `scripts/catalog.py` | Load, validate and normalise records. Pure library, no I/O side effects, no generation. |
| `scripts/generate_image_elements.py` | `--write` / `--check` generator producing the three `.bst` files per image. |
| `tests/test_catalog_schema.py` | The schema accepts valid records and rejects invalid ones. |
| `tests/test_catalog_conformance.py` | Every record truthfully describes its committed elements. |
| `tests/test_generated_elements.py` | Generated output is semantically equal to committed output. |
| `.github/workflows/image-catalog.yml` | CI drift gate. |
| `Justfile` | `verify` derives gates and smoke test from the record. |
| `docs/skills/add-new-image.md` | Rewritten: adding an image is adding a record. |

`scripts/catalog.py` is deliberately separate from the generator so that the `Justfile`, the tests, and any future tool can read records without importing generation logic.

---

### Task 1: Catalog schema, loader, and the first record

**Files:**
- Create: `catalog/schema.json`
- Create: `catalog/base.yaml`
- Create: `scripts/catalog.py`
- Test: `tests/test_catalog_schema.py`

**Interfaces:**
- Consumes: nothing.
- Produces: `catalog.load_record(path) -> dict`, `catalog.load_all() -> list[dict]`, `catalog.CANONICAL_EXCLUDE -> list[str]`, `catalog.compose_exclude(record) -> list[str]`, and `catalog.CatalogError`. Every later task imports these.

- [ ] **Step 1: Write the failing test**

Create `tests/test_catalog_schema.py`:

```python
"""The catalog schema is the contract for an image record."""

from pathlib import Path
import sys
import unittest

ROOT = Path(__file__).parents[1]
sys.path.insert(0, str(ROOT / "scripts"))

import catalog  # noqa: E402


def valid_record(**overrides):
    """A minimal record that passes validation.

    Negative tests start from this and change exactly one thing, so a test can
    only pass for the reason it names. An earlier draft used
    description: "x", which independently violated the schema's minLength and
    made three negative tests pass vacuously.
    """
    record = {
        "name": "probe",
        "kind": "distroless",
        "description": "A valid record used as a negative-test baseline",
        "size_ceiling_mib": 64,
        "stack": {"components": []},
    }
    record.update(overrides)
    return record


class SchemaTests(unittest.TestCase):
    def test_the_baseline_fixture_is_actually_valid(self):
        """Guards every negative test below: if this fails, they prove nothing."""
        self.assertEqual(catalog.validate(valid_record())["name"], "probe")

    def test_base_record_is_valid(self):
        record = catalog.load_record(ROOT / "catalog" / "base.yaml")
        self.assertEqual(record["name"], "base")
        self.assertEqual(record["kind"], "distroless")

    def test_missing_required_field_is_rejected(self):
        record = valid_record()
        del record["kind"]
        with self.assertRaises(catalog.CatalogError) as ctx:
            catalog.validate(record)
        self.assertIn("kind", str(ctx.exception))

    def test_unknown_field_is_rejected(self):
        with self.assertRaises(catalog.CatalogError) as ctx:
            catalog.validate(valid_record(nonsense=True))
        self.assertIn("nonsense", str(ctx.exception))

    def test_name_must_match_filename(self):
        with self.assertRaises(catalog.CatalogError) as ctx:
            catalog.load_record(ROOT / "catalog" / "base.yaml", expect_name="python")
        self.assertIn("filename", str(ctx.exception))

    def test_compose_exclude_is_canonical_by_default(self):
        record = catalog.load_record(ROOT / "catalog" / "base.yaml")
        self.assertEqual(catalog.compose_exclude(record), catalog.CANONICAL_EXCLUDE)

    def test_exclude_omit_requires_a_reason(self):
        record = valid_record(compose={"exclude_omit": [{"domain": "devel"}]})
        with self.assertRaises(catalog.CatalogError) as ctx:
            catalog.validate(record)
        self.assertIn("reason", str(ctx.exception))

    def test_shell_probe_is_rejected_on_a_distroless_record(self):
        record = valid_record(smoke={"args": [], "shell_probe": "true"})
        with self.assertRaises(catalog.CatalogError) as ctx:
            catalog.validate(record)
        self.assertIn("shell-enabled", str(ctx.exception))

    def test_an_empty_shell_probe_is_also_rejected(self):
        """Presence, not truthiness. An empty string is still a shell probe."""
        record = valid_record(smoke={"args": [], "shell_probe": ""})
        with self.assertRaises(catalog.CatalogError):
            catalog.validate(record)

    def test_shell_probe_is_allowed_on_a_shell_enabled_record(self):
        record = valid_record(kind="shell-enabled", smoke={"args": [], "shell_probe": "true"})
        self.assertEqual(catalog.validate(record)["kind"], "shell-enabled")

    def test_a_record_may_omit_entrypoint_and_smoke(self):
        """base and static have neither today; the schema must not force them."""
        record = valid_record()
        self.assertNotIn("entrypoint", record)
        self.assertNotIn("smoke", record)
        catalog.validate(record)


if __name__ == "__main__":
    unittest.main()
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd /var/home/jorge/src/fsdk-containers && python3 -m unittest discover -s tests -p 'test_catalog_schema.py' -v`
Expected: FAIL with `ModuleNotFoundError: No module named 'catalog'`

- [ ] **Step 3: Write the schema**

Create `catalog/schema.json`:

```json
{
  "$schema": "https://json-schema.org/draft/2020-12/schema",
  "$id": "https://github.com/projectbluefin/fsdk-containers/catalog/schema.json",
  "title": "fsdk-containers image record",
  "description": "The single declarative record for one published OCI image. Adding an image means adding one of these; every BuildStream element and every verification gate is derived from it.",
  "type": "object",
  "additionalProperties": false,
  "required": ["name", "kind", "description", "size_ceiling_mib", "stack"],
  "properties": {
    "name": {
      "type": "string",
      "pattern": "^[a-z0-9]([a-z0-9-]*[a-z0-9])?$",
      "description": "Image name. Must equal the filename stem and appear in elements/targets.json oci_images."
    },
    "kind": {
      "type": "string",
      "enum": ["distroless", "shell-enabled"],
      "description": "Selects the verification gate set. shell-enabled is a documented exception, currently only lab-runner."
    },
    "description": {
      "type": "string",
      "minLength": 10,
      "description": "Becomes org.opencontainers.image.description."
    },
    "entrypoint": {
      "type": "array",
      "minItems": 1,
      "items": {"type": "string", "pattern": "^/"},
      "description": "Absolute paths. Element 0 must exist and execute in the built image. OPTIONAL: omit it for images that genuinely have no entrypoint today (base, static). Generation must not invent one -- adding an Entrypoint to an image that lacks one is a behaviour change, which this plan forbids."
    },
    "smoke": {
      "type": "object",
      "description": "OPTIONAL: omit for images that have no smoke test in the Justfile today (base, static).",
      "additionalProperties": false,
      "required": ["args"],
      "properties": {
        "args": {
          "type": "array",
          "items": {"type": "string"},
          "description": "Arguments appended to the entrypoint to prove the image runs."
        },
        "entrypoint_override": {
          "type": "array",
          "items": {"type": "string"},
          "description": "Run this instead of the image entrypoint. Only for images whose entrypoint is not the thing under test."
        },
        "shell_probe": {
          "type": "string",
          "description": "Extra shell one-liner, permitted only when kind is shell-enabled."
        }
      }
    },
    "size_ceiling_mib": {
      "type": "integer",
      "minimum": 1,
      "description": "Uncompressed local podman size ceiling. Superseded by the ratchet in a later phase; kept here so this plan changes no behaviour."
    },
    "stack": {
      "type": "object",
      "additionalProperties": false,
      "required": ["components"],
      "properties": {
        "base": {
          "type": ["string", "null"],
          "description": "Stack element this one builds on, e.g. base/base-stack.bst. Null only for base itself."
        },
        "components": {
          "type": "array",
          "items": {"type": "string"},
          "description": "FSDK component elements, e.g. freedesktop-sdk.bst:components/python3.bst. Never platform.bst."
        },
        "extra_depends": {
          "type": "array",
          "items": {"type": "string"},
          "description": "Repo-local elements this stack needs, e.g. base/terminfo-ghostty.bst."
        }
      }
    },
    "compose": {
      "type": "object",
      "additionalProperties": false,
      "properties": {
        "exclude_omit": {
          "type": "array",
          "description": "Canonical exclude domains this image deliberately does NOT exclude. Every omission needs a reason, so divergence is declared rather than silent.",
          "items": {
            "type": "object",
            "additionalProperties": false,
            "required": ["domain", "reason"],
            "properties": {
              "domain": {
                "type": "string",
                "enum": ["debug", "devel", "doc", "locale", "shells", "static-blocklist", "tests", "vm-only"]
              },
              "reason": {"type": "string", "minLength": 20}
            }
          }
        }
      }
    },
    "slim": {
      "type": "object",
      "additionalProperties": false,
      "properties": {
        "extra": {
          "type": "string",
          "description": "Image-specific shell commands appended after the shared slim recipe. Phase 3 dependency-closure pruning is expected to delete most of these."
        }
      }
    },
    "gates": {
      "type": "object",
      "additionalProperties": false,
      "properties": {
        "require_paths": {
          "type": "array",
          "items": {"type": "string"},
          "description": "Rootfs paths (no leading slash) that must be present, checked against the exported tar listing."
        },
        "require_binaries": {
          "type": "array",
          "items": {"type": "string"},
          "description": "Basenames that must appear somewhere in the rootfs listing."
        }
      }
    },
    "keywords": {
      "type": "string",
      "description": "Verbatim value of the io.artifacthub.package.keywords label. This is the ONE non-obvious label that varies per image (measured: 7 distinct values across 7 images, e.g. lab-runner uses 'freedesktop-sdk,bluefin,ci' with no 'distroless'). It is transcribed, never derived, because deriving it would rewrite six images' labels."
    },
    "notes": {
      "type": "string",
      "description": "Free-form prose carried into the generated elements as a comment. Use for hard-won context that would otherwise be lost."
    }
  }
}
```

- [ ] **Step 4: Write the loader**

Create `scripts/catalog.py`:

```python
#!/usr/bin/env python3
"""Load and validate fsdk-containers image records.

A record in catalog/<name>.yaml is the single declarative description of one
published OCI image. This module is the only supported way to read one. It is
deliberately free of generation logic so the Justfile, the tests, and any
future tool can consume records without importing the generator.
"""
from __future__ import annotations

import json
from pathlib import Path

import yaml
from jsonschema import Draft202012Validator

REPO_ROOT = Path(__file__).resolve().parent.parent
CATALOG_DIR = REPO_ROOT / "catalog"
SCHEMA_PATH = CATALOG_DIR / "schema.json"

# The exclude set every distroless compose element uses. Measured 2026-08-21:
# 13 of 16 committed compose elements already match this exactly. Deviations
# must be declared via compose.exclude_omit with a reason.
CANONICAL_EXCLUDE = [
    "debug",
    "devel",
    "doc",
    "locale",
    "shells",
    "static-blocklist",
    "tests",
    "vm-only",
]


class CatalogError(Exception):
    """A record is missing, malformed, or contradicts its filename."""


def _validator() -> Draft202012Validator:
    schema = json.loads(SCHEMA_PATH.read_text())
    return Draft202012Validator(schema)


def validate(record: dict) -> dict:
    """Raise CatalogError if the record does not satisfy catalog/schema.json."""
    errors = sorted(_validator().iter_errors(record), key=lambda e: e.path)
    if errors:
        detail = "; ".join(
            f"{'/'.join(str(p) for p in e.absolute_path) or '<root>'}: {e.message}"
            for e in errors
        )
        raise CatalogError(f"invalid record: {detail}")
    if "shell_probe" in record.get("smoke", {}) and record["kind"] != "shell-enabled":
        raise CatalogError(
            f"{record['name']}: smoke.shell_probe requires kind: shell-enabled"
        )
    return record


def load_record(path: Path, expect_name: str | None = None) -> dict:
    """Load one record, validate it, and check it agrees with its filename."""
    path = Path(path)
    if not path.exists():
        raise CatalogError(f"no such record: {path}")
    record = yaml.safe_load(path.read_text())
    if not isinstance(record, dict):
        raise CatalogError(f"{path}: record must be a YAML mapping")
    validate(record)
    stem = path.stem
    if record["name"] != stem:
        raise CatalogError(
            f"{path}: name {record['name']!r} does not match filename stem {stem!r}"
        )
    if expect_name is not None and record["name"] != expect_name:
        raise CatalogError(
            f"{path}: expected record named {expect_name!r}, filename gives {stem!r}"
        )
    return record


def load_all() -> list[dict]:
    """Every record in catalog/, sorted by name."""
    records = [
        load_record(p) for p in sorted(CATALOG_DIR.glob("*.yaml"))
    ]
    return sorted(records, key=lambda r: r["name"])


def compose_exclude(record: dict) -> list[str]:
    """The exclude domains for this image, canonical minus declared omissions."""
    omitted = {
        entry["domain"]
        for entry in record.get("compose", {}).get("exclude_omit", [])
    }
    return [d for d in CANONICAL_EXCLUDE if d not in omitted]
```

- [ ] **Step 5: Write the base record**

Create `catalog/base.yaml`. The values come from `elements/base/base-stack.bst`, `elements/base/base-runtime.bst`, `elements/oci/base.bst`, and the `base)` arm of the `Justfile` verify case statement:

```yaml
# The distroless foundation every other image is carved from.
name: base
kind: distroless
description: Distroless base image carved from freedesktop-sdk
# No entrypoint and no smoke block. elements/oci/base.bst sets no Entrypoint,
# and just verify has no `base` smoke arm. Declaring either would make Task 6
# publish an image config that differs from today's -- forbidden by this plan.
size_ceiling_mib: 64
stack:
  base: null
  components:
    - freedesktop-sdk.bst:public-stacks/runtime-gnu.bst
    - freedesktop-sdk.bst:public-stacks/runtime-minimal.bst
    - freedesktop-sdk.bst:components/ca-certificates.bst
    - freedesktop-sdk.bst:components/tzdata.bst
    - freedesktop-sdk.bst:components/os-release.bst
    - freedesktop-sdk.bst:integration/extra-fs.bst
    - freedesktop-sdk.bst:integration/ldconfig.bst
  extra_depends:
    - base/terminfo-ghostty.bst
gates:
  require_paths:
    - usr/share/zoneinfo/UTC
notes: |
  runtime-gnu is a deliberate dependency, not an accident. FSDK 26.08beta.2
  moved integration/ldconfig.bst's runtime-gnu dependency from depends: to
  build-depends:, so a shell no longer reaches the composed layer implicitly.
  The ca-certificates and ldconfig integration commands are shell scripts and
  need /bin/sh staged to run at all. The shared SLIM recipe removes the shell
  again before the image is built.

  terminfo-ghostty exists because ncurses ships the entry only as "ghostty"
  while Ghostty sets TERM=xterm-ghostty (#105).
```

- [ ] **Step 6: Run tests to verify they pass**

Run: `cd /var/home/jorge/src/fsdk-containers && python3 -m unittest discover -s tests -p 'test_catalog_schema.py' -v`
Expected: PASS, 11 tests.

- [ ] **Step 7: Commit**

```bash
git add catalog/schema.json catalog/base.yaml scripts/catalog.py tests/test_catalog_schema.py
git commit -m "feat(catalog): add the image record schema and loader

One YAML record per image is intended to become the only thing a human writes
to add an image. This lands the contract and the loader, plus the first record
describing the base image. Nothing consumes it yet.

Co-authored-by: Copilot <223556219+Copilot@users.noreply.github.com>"
```

---

### Task 2: Backfill records for the remaining six images

**Files:**
- Create: `catalog/static.yaml`, `catalog/python.yaml`, `catalog/skopeo.yaml`, `catalog/buildah.yaml`, `catalog/qemu-img.yaml`, `catalog/lab-runner.yaml`
- Test: `tests/test_catalog_conformance.py`

**Interfaces:**
- Consumes: `catalog.load_all()`, `catalog.CatalogError` from Task 1.
- Produces: a complete `catalog/` covering every entry in `elements/targets.json` `oci_images`.

- [ ] **Step 1: Write the failing test**

Create `tests/test_catalog_conformance.py`:

```python
"""Every published image has a record, and every record has an image."""

import json
from pathlib import Path
import sys
import unittest

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


if __name__ == "__main__":
    unittest.main()
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd /var/home/jorge/src/fsdk-containers && python3 -m unittest discover -s tests -p 'test_catalog_conformance.py' -v`
Expected: FAIL — `published images with no catalog record` lists six names.

- [ ] **Step 3: Write the six records**

Read each image's three committed elements plus its `Justfile` verify arm, and transcribe. Do not invent values; every field must be traceable to a committed file.

`catalog/python.yaml`:

```yaml
name: python
kind: distroless
description: Distroless Python 3 runtime carved from freedesktop-sdk
entrypoint: ["/usr/bin/python3"]
smoke:
  args: ["--version"]
size_ceiling_mib: 144
stack:
  base: base/base-stack.bst
  components:
    - freedesktop-sdk.bst:components/python3.bst
gates:
  require_paths:
    - usr/share/zoneinfo/UTC
slim:
  extra: |
    set -eu
    L=/layer
    rm -rf "$L"/usr/lib/python*/test \
           "$L"/usr/lib/python*/*/test \
           "$L"/usr/lib/python*/*/tests \
           "$L"/usr/lib/python*/ensurepip \
           "$L"/usr/lib/python*/idlelib \
           "$L"/usr/lib/python*/tkinter \
           "$L"/usr/lib/python*/turtledemo \
           "$L"/usr/lib/python*/turtle.py \
           "$L"/usr/lib/python*/lib2to3 \
           "$L"/usr/lib/python*/pydoc_data \
           "$L"/usr/lib/python*/__phello__ \
           "$L"/usr/lib/python*/config-*
```

> **Transcription rule for `slim.extra`:** copy the block verbatim from the
> committed `elements/oci/<name>.bst` `config.commands` entry that follows
> `"%{slim-distroless-commands}"`. Byte-for-byte. Task 4 asserts equality, so
> any paraphrase will fail the build.

> **Transcription rule for `keywords`:** copy the
> `io.artifacthub.package.keywords` label verbatim from the committed
> `elements/oci/<name>.bst`. Measured 2026-08-21, all seven images have a
> DIFFERENT value — `base` has `distroless,freedesktop-sdk,bluefin`, most
> others append their own name, and `lab-runner` has
> `freedesktop-sdk,bluefin,ci` with no `distroless` at all. This is the only
> non-obvious label that varies, and deriving it would rewrite six images.

> **Transcription rule for `entrypoint`:** an image gets an `entrypoint` in its
> record if and only if its committed `elements/oci/<name>.bst` contains an
> `Entrypoint:` key. Measured 2026-08-21: `buildah`, `lab-runner`, `python` and
> `qemu-img` have one; `base`, `skopeo` and `static` do NOT. `skopeo` is the
> trap — `just verify` smoke-tests it with `podman run --rm "$REF" skopeo
> --version`, passing `skopeo` as an *argument*, which is only possible because
> the image has no entrypoint. Its record must omit `entrypoint` and use
> `smoke.args: ["skopeo", "--version"]`.

`catalog/skopeo.yaml` — note the entrypoint override, because `skopeo`'s smoke
test runs `skopeo --version` as an argument rather than through the entrypoint:

```yaml
name: skopeo
kind: distroless
description: Distroless skopeo image carved from freedesktop-sdk
keywords: distroless,freedesktop-sdk,bluefin,skopeo
# No entrypoint: elements/oci/skopeo.bst sets none, which is why just verify
# can run `podman run --rm "$REF" skopeo --version` with skopeo as an argument.
smoke:
  args: ["skopeo", "--version"]
size_ceiling_mib: 224
stack:
  base: base/base-stack.bst
  components:
    - freedesktop-sdk.bst:components/skopeo.bst
    - freedesktop-sdk.bst:components/containers-common.bst
    - freedesktop-sdk.bst:components/gpgme.bst
    - freedesktop-sdk.bst:components/libassuan.bst
    - freedesktop-sdk.bst:components/sqlite.bst
    - freedesktop-sdk.bst:components/libgpg-error.bst
    - freedesktop-sdk.bst:components/glib.bst
    - freedesktop-sdk.bst:components/pkg-config.bst
gates:
  require_paths:
    - usr/share/zoneinfo/UTC
```

Fill `stack.components` for `buildah`, `qemu-img` and `static` the same way,
from their committed `*-stack.bst` `depends:` lists, and `size_ceiling_mib` from
the `Justfile` case statement: `static` 80, `qemu-img` 192, `buildah` 256.

`catalog/lab-runner.yaml` carries the shell-enabled gate set and its full CLI
contract, transcribed from the `lab-runner` arm of `just verify`.

> **`stack.components` below is deliberately elided.** `lab-runner-stack.bst`
> depends on 26 elements — 17 FSDK components (`curl`, `git`, `jq`, `python3`,
> `python3-pyyaml`, `openssh`, `tar`, `gzip`, `which`, `findutils`, `gawk`,
> `procps`, `diffutils`, `patch`, `less`, `file`, `bubblewrap`), 8 repo-local
> `lab-runner/*.bst` elements, and `skopeo/skopeo-stack.bst`. Transcribe all of
> them from the committed file. Task 3's conformance test fails loudly if you
> do not; that failure was reproduced while writing this plan.

```yaml
name: lab-runner
kind: shell-enabled
description: Shell-enabled CI/CD utility container for Project Bluefin lab workflows
entrypoint: ["/usr/bin/bash"]
smoke:
  entrypoint_override: ["/usr/bin/argo"]
  args: ["version", "--short"]
  shell_probe: >-
    kubectl version --client >/dev/null && curl --version && git --version &&
    jq --version && python3 --version && skopeo --version
size_ceiling_mib: 640
compose:
  exclude_omit:
    - domain: shells
      reason: >-
        lab-runner is the documented shell-enabled exception, so the fish and
        zsh data directories in the shells domain are harmless and excluding
        them buys nothing. Declared rather than silently divergent.
stack:
  base: base/base-stack.bst
  components:
    # TRANSCRIBE ALL 17 FSDK COMPONENTS FROM elements/lab-runner/lab-runner-stack.bst
    - freedesktop-sdk.bst:components/curl.bst
    - freedesktop-sdk.bst:components/git.bst
    # ... and the remaining 15
  extra_depends:
    # TRANSCRIBE ALL 9 REPO-LOCAL DEPENDENCIES
    - skopeo/skopeo-stack.bst
    - lab-runner/argo.bst
    # ... and the remaining 7

gates:
  require_binaries:
    - bash
    - argo
    - just
    - kubectl
    - skopeo
    - shellcheck
    - hadolint
    - actionlint
    - which
    - xargs
    - awk
    - ps
    - tar
    - diff
    - patch
    - less
    - file
    - gzip
    - bwrap
  require_paths:
    - usr/share/terminfo/x/xterm-256color
    - usr/share/terminfo/s/screen-256color
    - usr/share/terminfo/t/tmux-direct
    - usr/share/terminfo/x/xterm-direct
    - usr/share/terminfo/x/xterm-ghostty
notes: |
  gzip is not optional alongside tar: GNU tar execs gzip as a child process for
  .tar.gz streams, so tar being present is not sufficient (#159).
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd /var/home/jorge/src/fsdk-containers && python3 -m unittest discover -s tests -p 'test_catalog*.py' -v`
Expected: PASS, 9 tests.

- [ ] **Step 5: Commit**

```bash
git add catalog/ tests/test_catalog_conformance.py
git commit -m "feat(catalog): backfill records for all seven published images

Each record is transcribed from that image's committed stack, compose and oci
elements plus its Justfile verify arm. No values are invented. A coverage test
asserts catalog/ and targets.json oci_images describe the same set.

Co-authored-by: Copilot <223556219+Copilot@users.noreply.github.com>"
```

---

### Task 3: Prove the records describe reality

**Files:**
- Modify: `tests/test_catalog_conformance.py`
- Modify: `catalog/go.yaml` is **not** in scope — only the seven published images.
- Possibly modify: `catalog/lab-runner.yaml` (if its `exclude_omit` reason needs adjusting once measured)

**Interfaces:**
- Consumes: `catalog.load_all()`, `catalog.compose_exclude()` from Task 1.
- Produces: a test that fails if any record and its committed elements disagree. This is the gate that makes Task 4 safe.

This is the most important task in the plan. Generation is only safe if the records are already true.

- [ ] **Step 1: Write the failing test**

Append to `tests/test_catalog_conformance.py`:

```python
import yaml


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
                expected = []
                if record["stack"].get("base"):
                    expected.append(record["stack"]["base"])
                expected += record["stack"]["components"]
                expected += record["stack"].get("extra_depends", [])
                self.assertEqual(
                    sorted(committed["depends"]),
                    sorted(expected),
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
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd /var/home/jorge/src/fsdk-containers && python3 -m unittest discover -s tests -p 'test_catalog_conformance.py' -v`
Expected: FAIL. Each failure is either a transcription error in a record (fix the record) or a genuine undocumented deviation (declare it).

- [ ] **Step 3: Fix every disagreement**

For each failure, decide and act:

- **Transcription error** — the record is wrong. Correct the record.
- **Genuine deviation** — the element differs from canonical. Add a
  `compose.exclude_omit` entry with a reason of at least 20 characters, or a
  `slim.extra` block. Do **not** change any element file in this task; changing
  an element changes an image, and this task is required to be inert.

Two deviations are already known and expected here:

| Image | Deviation | Action |
| --- | --- | --- |
| `lab-runner` | compose omits `shells` | Declare via `exclude_omit`, reason already drafted in Task 2 |
| `go` | compose omits `devel` | Out of scope — `go` is not in `targets.json` `oci_images` and has no record |

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd /var/home/jorge/src/fsdk-containers && python3 -m unittest discover -s tests -p 'test_catalog*.py' -v`
Expected: PASS.

- [ ] **Step 5: Verify no element file was touched**

Run: `cd /var/home/jorge/src/fsdk-containers && git status --short elements/`
Expected: empty output. If any element changed, revert it — this task must not alter a single image.

- [ ] **Step 6: Commit**

```bash
git add tests/test_catalog_conformance.py catalog/
git commit -m "test(catalog): assert every record truthfully describes its elements

Generation is only safe if the records already match what is committed. This
compares each record against its stack depends, compose exclude set, and the
extra slim commands in its oci element, and turns lab-runner's previously
silent shells omission into a declared one with a reason.

No element file is modified; no image changes.

Co-authored-by: Copilot <223556219+Copilot@users.noreply.github.com>"
```

---

### Task 4: Generate the compose elements

**Files:**
- Create: `scripts/generate_image_elements.py`
- Test: `tests/test_generated_elements.py`
- Modify: `elements/<name>/<name>-runtime.bst` for all seven images (adopting generated output)

**Interfaces:**
- Consumes: `catalog.load_all()`, `catalog.compose_exclude()`.
- Produces: `generate_image_elements.render_compose(record) -> str`, `render_stack(record) -> str` (Task 5), `render_oci(record) -> str` (Task 6), and a `main()` supporting `--write` and `--check`.

Compose is generated first because it is the smallest and the most uniform — 13 of 16 committed files are already identical.

- [ ] **Step 1: Write the failing test**

Create `tests/test_generated_elements.py`:

```python
"""Generated elements must be semantically identical to committed ones."""

from pathlib import Path
import sys
import unittest

import yaml

ROOT = Path(__file__).parents[1]
sys.path.insert(0, str(ROOT / "scripts"))

import catalog  # noqa: E402
import generate_image_elements as gen  # noqa: E402


class ComposeGenerationTests(unittest.TestCase):
    def test_generated_compose_matches_committed(self):
        for record in catalog.load_all():
            with self.subTest(image=record["name"]):
                name = record["name"]
                committed_path = ROOT / "elements" / name / f"{name}-runtime.bst"
                committed = yaml.safe_load(committed_path.read_text())
                generated = yaml.safe_load(gen.render_compose(record))
                self.assertEqual(generated["kind"], committed["kind"])
                self.assertEqual(
                    generated["build-depends"], committed["build-depends"]
                )
                self.assertEqual(
                    sorted(generated["config"]["exclude"]),
                    sorted(committed["config"]["exclude"]),
                )

    def test_generated_compose_is_valid_yaml_with_a_header(self):
        record = catalog.load_record(ROOT / "catalog" / "base.yaml")
        text = gen.render_compose(record)
        self.assertIn("DO NOT EDIT", text)
        self.assertIn("catalog/base.yaml", text)
        self.assertIsInstance(yaml.safe_load(text), dict)

    def test_check_mode_passes_on_a_clean_tree(self):
        self.assertEqual(gen.check(), [])


if __name__ == "__main__":
    unittest.main()
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd /var/home/jorge/src/fsdk-containers && python3 -m unittest discover -s tests -p 'test_generated_elements.py' -v`
Expected: FAIL with `ModuleNotFoundError: No module named 'generate_image_elements'`

- [ ] **Step 3: Write the generator**

Create `scripts/generate_image_elements.py`:

```python
#!/usr/bin/env python3
"""Generate BuildStream elements from catalog/<name>.yaml records.

Usage:
    python3 scripts/generate_image_elements.py --write   # regenerate elements
    python3 scripts/generate_image_elements.py --check   # fail if stale (CI gate)

Every file this writes carries a DO-NOT-EDIT header naming its record. Editing
a generated element by hand is always wrong: the change is silently reverted on
the next --write, and the --check gate fails the pull request in the meantime.
Change the record instead.
"""
from __future__ import annotations

import argparse
import sys
from pathlib import Path

import yaml

import catalog

REPO_ROOT = catalog.REPO_ROOT
ELEMENTS = REPO_ROOT / "elements"


def _header(name: str, what: str) -> str:
    return (
        f"# DO NOT EDIT. Generated from catalog/{name}.yaml by\n"
        f"# scripts/generate_image_elements.py ({what}).\n"
        f"# Change the record, then run: just catalog-write\n"
    )


def render_compose(record: dict) -> str:
    """The compose element that chisels a stack down to runtime-only."""
    name = record["name"]
    lines = [_header(name, "compose")]
    lines.append("kind: compose")
    lines.append(
        f"description: Chisel the {name} stack down to runtime-only, distroless."
        if record["kind"] == "distroless"
        else f"description: Chisel the {name} stack down to its runtime contract."
    )
    lines.append("")
    lines.append("build-depends:")
    lines.append(f"  - {name}/{name}-stack.bst")
    lines.append("")
    lines.append("config:")
    lines.append("  exclude:")

    omissions = {
        e["domain"]: e["reason"]
        for e in record.get("compose", {}).get("exclude_omit", [])
    }
    for domain in catalog.compose_exclude(record):
        lines.append(f"    - {domain}")
    for domain, reason in sorted(omissions.items()):
        wrapped = " ".join(reason.split())
        lines.append(f"    # NOT excluded -- {domain}: {wrapped}")
    return "\n".join(lines) + "\n"


RENDERERS = {
    "compose": (render_compose, lambda n: ELEMENTS / n / f"{n}-runtime.bst"),
}


def _targets() -> list[tuple[Path, str]]:
    out = []
    for record in catalog.load_all():
        for renderer, path_for in RENDERERS.values():
            out.append((path_for(record["name"]), renderer(record)))
    return out


def write() -> list[Path]:
    written = []
    for path, text in _targets():
        path.parent.mkdir(parents=True, exist_ok=True)
        if not path.exists() or path.read_text() != text:
            path.write_text(text)
            written.append(path)
    return written


def check() -> list[Path]:
    """Paths whose committed content differs from what the record generates."""
    return [
        path
        for path, text in _targets()
        if not path.exists() or path.read_text() != text
    ]


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    group = parser.add_mutually_exclusive_group(required=True)
    group.add_argument("--write", action="store_true", help="regenerate elements")
    group.add_argument("--check", action="store_true", help="fail if stale")
    args = parser.parse_args()

    if args.write:
        for path in write():
            print(f"wrote {path.relative_to(REPO_ROOT)}")
        return 0

    stale = check()
    for path in stale:
        print(
            f"STALE: {path.relative_to(REPO_ROOT)} does not match its catalog "
            f"record. Run: just catalog-write",
            file=sys.stderr,
        )
    return 1 if stale else 0


if __name__ == "__main__":
    raise SystemExit(main())
```

- [ ] **Step 4: Run the semantic-equality test before adopting output**

Run: `cd /var/home/jorge/src/fsdk-containers && python3 -m unittest discover -s tests -p 'test_generated_elements.py' -v -k test_generated_compose_matches_committed`
Expected: PASS. This proves the generator reproduces current behaviour **before** any file is overwritten. If it fails, fix the generator or the record — never adopt output that differs semantically.

- [ ] **Step 5: Adopt the generated output**

```bash
cd /var/home/jorge/src/fsdk-containers
python3 scripts/generate_image_elements.py --write
git --no-pager diff --stat elements/
git --no-pager diff elements/
```

Read the whole diff. It should contain only comment and formatting changes plus
the DO-NOT-EDIT header. **If any `exclude` domain is added or removed, stop** —
that is a behaviour change and the record is wrong.

- [ ] **Step 6: Prove the images did not change**

Run: `cd /var/home/jorge/src/fsdk-containers && just validate`
Expected: the element graph resolves with no errors.

Run: `cd /var/home/jorge/src/fsdk-containers && just build && just verify`
Expected: build succeeds and all five distroless gates plus the size check pass for `base`.

- [ ] **Step 7: Run the full test suite**

Run: `cd /var/home/jorge/src/fsdk-containers && python3 -m unittest discover -s tests -v`
Expected: PASS.

- [ ] **Step 8: Commit**

```bash
git add scripts/generate_image_elements.py tests/test_generated_elements.py elements/
git commit -m "feat(catalog): generate compose elements from image records

Compose is the most uniform element -- 13 of 16 committed exclude sets were
already byte-identical -- so it goes first. The generator is proven faithful by
a semantic-equality test against the committed files before it takes ownership,
and lab-runner's shells omission now renders as a comment naming its reason.

just validate, just build and just verify all pass unchanged.

Co-authored-by: Copilot <223556219+Copilot@users.noreply.github.com>"
```

---

### Task 5: Generate the stack elements

**Files:**
- Modify: `scripts/generate_image_elements.py`
- Modify: `tests/test_generated_elements.py`
- Modify: `elements/<name>/<name>-stack.bst` for all seven images

**Interfaces:**
- Consumes: `catalog.load_all()`, `gen.render_compose` from Task 4.
- Produces: `gen.render_stack(record) -> str`, registered in `RENDERERS` under key `"stack"`.

- [ ] **Step 1: Write the failing test**

Add to `tests/test_generated_elements.py`:

```python
class StackGenerationTests(unittest.TestCase):
    def test_generated_stack_matches_committed(self):
        for record in catalog.load_all():
            with self.subTest(image=record["name"]):
                name = record["name"]
                committed = yaml.safe_load(
                    (ROOT / "elements" / name / f"{name}-stack.bst").read_text()
                )
                generated = yaml.safe_load(gen.render_stack(record))
                self.assertEqual(generated["kind"], "stack")
                self.assertEqual(
                    sorted(generated["depends"]), sorted(committed["depends"])
                )

    def test_notes_are_carried_into_the_generated_stack(self):
        record = catalog.load_record(ROOT / "catalog" / "base.yaml")
        text = gen.render_stack(record)
        self.assertIn("runtime-gnu is a deliberate dependency", text)
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd /var/home/jorge/src/fsdk-containers && python3 -m unittest discover -s tests -p 'test_generated_elements.py' -v -k StackGenerationTests`
Expected: FAIL with `AttributeError: module 'generate_image_elements' has no attribute 'render_stack'`

- [ ] **Step 3: Implement `render_stack`**

Add to `scripts/generate_image_elements.py`, above `RENDERERS`:

```python
def render_stack(record: dict) -> str:
    """The stack element listing everything this image depends on."""
    name = record["name"]
    lines = [_header(name, "stack")]
    lines.append("kind: stack")
    # Serialise through yaml rather than interpolating. static's description
    # contains ": ", which an f-string would emit as a nested mapping and
    # produce invalid YAML. Found by the Task 5 implementer before any file
    # was written.
    lines.append(yaml.dump({"description": record["description"]},
                           default_flow_style=False, width=10**6).rstrip())

    if record.get("notes"):
        lines.append("")
        for line in record["notes"].rstrip().splitlines():
            lines.append(f"# {line}".rstrip())

    lines.append("")
    lines.append("depends:")
    if record["stack"].get("base"):
        lines.append(f"  - {record['stack']['base']}")
    for component in record["stack"]["components"]:
        lines.append(f"  - {component}")
    for extra in record["stack"].get("extra_depends", []):
        lines.append(f"  - {extra}")
    return "\n".join(lines) + "\n"
```

and extend the registry:

```python
RENDERERS = {
    "stack": (render_stack, lambda n: ELEMENTS / n / f"{n}-stack.bst"),
    "compose": (render_compose, lambda n: ELEMENTS / n / f"{n}-runtime.bst"),
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd /var/home/jorge/src/fsdk-containers && python3 -m unittest discover -s tests -p 'test_generated_elements.py' -v`
Expected: PASS.

- [ ] **Step 5: Adopt output and prove nothing changed**

```bash
cd /var/home/jorge/src/fsdk-containers
python3 scripts/generate_image_elements.py --write
git --no-pager diff elements/
just validate
just build && just verify
```

Expected: the diff touches only comments, ordering and the header. `just verify` passes. **Any added or removed `depends` entry is a behaviour change — stop and fix the record.**

- [ ] **Step 6: Commit**

```bash
git add scripts/generate_image_elements.py tests/test_generated_elements.py elements/
git commit -m "feat(catalog): generate stack elements from image records

Stack depends are now derived from the record, with each record's notes block
rendered as the element's comment header so hard-won context survives
generation rather than being lost to it.

Co-authored-by: Copilot <223556219+Copilot@users.noreply.github.com>"
```

---

### Task 6: Generate the OCI script elements

**Files:**
- Modify: `scripts/generate_image_elements.py`
- Modify: `tests/test_generated_elements.py`
- Modify: `elements/oci/<name>.bst` for all seven images

**Interfaces:**
- Consumes: everything from Tasks 4 and 5.
- Produces: `gen.render_oci(record) -> str`, registered in `RENDERERS` under key `"oci"`.

This is the largest element and carries the label boilerplate that is currently duplicated verbatim seven times.

- [ ] **Step 1: Write the failing test**

Add to `tests/test_generated_elements.py`:

```python
SHARED_LABELS = {
    "org.opencontainers.image.vendor": "Project Bluefin",
    "org.opencontainers.image.licenses": "Apache-2.0",
    "org.opencontainers.image.url": "https://github.com/projectbluefin/fsdk-containers",
    "org.opencontainers.image.source": "https://github.com/projectbluefin/fsdk-containers",
    "io.artifacthub.package.license": "Apache-2.0",
    "io.artifacthub.package.category": "integration-delivery",
}


class OciGenerationTests(unittest.TestCase):
    def test_generated_oci_matches_committed_build_depends(self):
        for record in catalog.load_all():
            with self.subTest(image=record["name"]):
                name = record["name"]
                committed = yaml.safe_load(
                    (ROOT / "elements" / "oci" / f"{name}.bst").read_text()
                )
                generated = yaml.safe_load(gen.render_oci(record))
                self.assertEqual(generated["kind"], "script")
                self.assertEqual(
                    generated["build-depends"], committed["build-depends"]
                )
                self.assertEqual(generated["variables"], committed["variables"])

    def test_slim_recipe_is_always_the_first_command(self):
        for record in catalog.load_all():
            with self.subTest(image=record["name"]):
                generated = yaml.safe_load(gen.render_oci(record))
                first = generated["config"]["commands"][0]
                expected = (
                    "%{slim-shell-enabled-commands}"
                    if record["kind"] == "shell-enabled"
                    else "%{slim-distroless-commands}"
                )
                self.assertEqual(first, expected)

    def test_every_image_carries_the_shared_labels(self):
        for record in catalog.load_all():
            with self.subTest(image=record["name"]):
                text = gen.render_oci(record)
                for key, value in SHARED_LABELS.items():
                    self.assertIn(f"'{key}': '{value}'", text)

    def test_slim_extra_is_emitted_verbatim(self):
        record = catalog.load_record(ROOT / "catalog" / "python.yaml")
        generated = yaml.safe_load(gen.render_oci(record))
        commands = generated["config"]["commands"]
        self.assertIn(
            record["slim"]["extra"].strip(),
            [c.strip() for c in commands],
        )
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd /var/home/jorge/src/fsdk-containers && python3 -m unittest discover -s tests -p 'test_generated_elements.py' -v -k OciGenerationTests`
Expected: FAIL with `AttributeError: module 'generate_image_elements' has no attribute 'render_oci'`

- [ ] **Step 3: Implement `render_oci`**

Add to `scripts/generate_image_elements.py`:

```python
SHARED_LABELS = [
    ("org.opencontainers.image.vendor", "Project Bluefin"),
    ("org.opencontainers.image.licenses", "Apache-2.0"),
    (
        "org.opencontainers.image.url",
        "https://github.com/projectbluefin/fsdk-containers",
    ),
    (
        "org.opencontainers.image.source",
        "https://github.com/projectbluefin/fsdk-containers",
    ),
    (
        "io.artifacthub.package.readme-url",
        "https://raw.githubusercontent.com/projectbluefin/fsdk-containers/main/README.md",
    ),
    ("io.artifacthub.package.logo-url", "https://projectbluefin.io/logo.png"),
    ("io.artifacthub.package.license", "Apache-2.0"),
    (
        "io.artifacthub.package.maintainers",
        '[{"name":"Project Bluefin","email":"maintainers@projectbluefin.io"}]',
    ),
    ("io.artifacthub.package.category", "integration-delivery"),
]
# NOT in SHARED_LABELS: io.artifacthub.package.keywords. It is the one
# non-obvious label that genuinely varies per image -- 7 distinct values across
# 7 images. Hardcoding a shared value here would have rewritten six images'
# labels, which this plan forbids. It comes from the record, verbatim.


def render_oci(record: dict) -> str:
    """The script element that slims the layer and builds the OCI image."""
    name = record["name"]
    slim_var = (
        "%{slim-shell-enabled-commands}"
        if record["kind"] == "shell-enabled"
        else "%{slim-distroless-commands}"
    )
    lines = [_header(name, "oci")]
    lines.append("kind: script")
    lines.append("")
    lines.append("build-depends:")
    # FSDK 26.08 removed the shell from runtime-minimal, so the script sandbox
    # no longer gets /bin/sh implicitly. The SLIM recipe is a shell script, so
    # its interpreter is declared explicitly.
    lines.append("  - freedesktop-sdk.bst:bootstrap/bash.bst")
    lines.append("  - freedesktop-sdk.bst:bootstrap/coreutils.bst")
    lines.append("  - freedesktop-sdk.bst:components/oci-builder.bst")
    lines.append("  - base/base-init-script.bst")
    lines.append(f"  - filename: {name}/{name}-runtime.bst")
    lines.append("    config:")
    lines.append("      location: /layer")
    lines.append("")
    lines.append("variables:")
    lines.append("  (@):")
    lines.append("    - include/slim.yml")
    lines.append("    - include/fsdk-version.yml")
    lines.append("")
    lines.append("config:")
    lines.append("  commands:")
    lines.append(f'    - "{slim_var}"')

    extra = record.get("slim", {}).get("extra")
    if extra:
        lines.append("    - |")
        for line in extra.rstrip().splitlines():
            lines.append(f"      {line}".rstrip())

    lines.append("    - |")
    lines.append("      if [ -d /initial_scripts ]; then")
    lines.append("        for i in /initial_scripts/*; do")
    lines.append('          "${i}" /layer')
    lines.append("        done")
    lines.append("      fi")

    lines.append("    - |")
    lines.append('      cd "%{install-root}"')
    lines.append("      build-oci <<EOF")
    lines.append("      mode: oci")
    lines.append("      gzip: disabled")
    lines.append("      images:")
    lines.append("      - os: linux")
    lines.append('        architecture: "%{go-arch}"')
    lines.append("        layer: /layer")
    lines.append(f'        comment: "fsdk-containers {name} image"')
    lines.append("        config:")
    # Only images that declare an entrypoint get one. base and static have no
    # Entrypoint in their committed oci elements; inventing one here would
    # change a published image, which this plan forbids.
    if record.get("entrypoint"):
        lines.append("          Entrypoint:")
        for part in record["entrypoint"]:
            lines.append(f"          - {part}")
    lines.append("          Labels:")
    lines.append(f"            'org.opencontainers.image.title': '{name}'")
    lines.append(
        f"            'org.opencontainers.image.description': "
        f"'{record['description']}'"
    )
    for key, value in SHARED_LABELS:
        lines.append(f"            '{key}': '{value}'")
    keywords = record.get("keywords", "distroless,freedesktop-sdk,bluefin")
    lines.append(f"            'io.artifacthub.package.keywords': '{keywords}'")
    lines.append("        index-annotations:")
    lines.append(
        f"          'org.opencontainers.image.ref.name': "
        f"'ghcr.io/projectbluefin/{name}:%{{fsdk-version}}'"
    )
    lines.append("      EOF")
    return "\n".join(lines) + "\n"
```

and register it:

```python
RENDERERS = {
    "stack": (render_stack, lambda n: ELEMENTS / n / f"{n}-stack.bst"),
    "compose": (render_compose, lambda n: ELEMENTS / n / f"{n}-runtime.bst"),
    "oci": (render_oci, lambda n: ELEMENTS / "oci" / f"{n}.bst"),
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd /var/home/jorge/src/fsdk-containers && python3 -m unittest discover -s tests -p 'test_generated_elements.py' -v`
Expected: PASS.

- [ ] **Step 5: Compare against committed output before adopting**

```bash
cd /var/home/jorge/src/fsdk-containers
python3 scripts/generate_image_elements.py --write
git --no-pager diff elements/oci/
```

Read every line. Expected differences: comment wording, key ordering, and the
added explicit `Entrypoint`. **An `Entrypoint` appearing where the committed
element had none is a real change** — confirm against the `Justfile` smoke test
that the image already behaves that way (e.g. `python --version` works because
the entrypoint is already `/usr/bin/python3`). If any image's entrypoint is not
already what the record declares, fix the record.

- [ ] **Step 6: Build and verify every image**

```bash
cd /var/home/jorge/src/fsdk-containers
for img in base static skopeo lab-runner python buildah qemu-img; do
  BUILD_IMAGE_NAME="$img" just build || exit 1
  BUILD_IMAGE_NAME="$img" just verify || exit 1
done
```

Expected: all seven build and pass their gates, sizes under their ceilings.

- [ ] **Step 7: Commit**

```bash
git add scripts/generate_image_elements.py tests/test_generated_elements.py elements/oci/
git commit -m "feat(catalog): generate oci script elements from image records

The label block was duplicated verbatim across all seven oci elements; it now
lives once in the generator. Entrypoints become explicit and declared rather
than implied by the Justfile smoke test.

All seven images build and pass just verify.

Co-authored-by: Copilot <223556219+Copilot@users.noreply.github.com>"
```

---

### Task 7: Gate drift in CI

**Files:**
- Create: `.github/workflows/image-catalog.yml`
- Modify: `Justfile` (add `catalog-write` and `catalog-check` recipes)

**Interfaces:**
- Consumes: `generate_image_elements.main()` `--check` from Task 4.
- Produces: `just catalog-write`, `just catalog-check`.

Without this gate the generated elements drift the moment someone hand-edits one, and a stale element silently ships a different image.

- [ ] **Step 1: Add the just recipes**

Add to `Justfile`, next to the other `[group('test')]` recipes:

```just
# Regenerate every BuildStream element from its catalog/<name>.yaml record.
[group('build')]
catalog-write:
    python3 scripts/generate_image_elements.py --write

# Fail if any generated element does not match its catalog record.
[group('test')]
catalog-check:
    python3 scripts/generate_image_elements.py --check
    python3 -m unittest discover -s tests -p 'test_catalog*.py' -v
    python3 -m unittest discover -s tests -p 'test_generated*.py' -v
```

- [ ] **Step 2: Verify the recipes work**

Run: `cd /var/home/jorge/src/fsdk-containers && just catalog-check`
Expected: PASS, no stale files.

- [ ] **Step 3: Prove the gate actually catches drift**

```bash
cd /var/home/jorge/src/fsdk-containers
printf '\n# hand edit\n' >> elements/python/python-runtime.bst
just catalog-check; echo "exit=$?"
git checkout elements/python/python-runtime.bst
```

Expected: `STALE: elements/python/python-runtime.bst ...` and `exit=1`. A gate
that has never been seen to fail is not a gate.

- [ ] **Step 4: Write the workflow**

Create `.github/workflows/image-catalog.yml`, mirroring `skill-catalog.yml`:

```yaml
name: image-catalog

# Every BuildStream element for an OCI image is generated from its
# catalog/<name>.yaml record. Without a gate they drift the moment someone
# hand-edits an element, and a stale element silently ships a different image
# than the record describes.

on:
  pull_request:
    paths:
      - 'catalog/**'
      - 'elements/**'
      - 'scripts/catalog.py'
      - 'scripts/generate_image_elements.py'
      - 'tests/test_catalog*.py'
      - 'tests/test_generated*.py'
  push:
    branches: [main]
    paths:
      - 'catalog/**'
      - 'elements/**'
      - 'scripts/catalog.py'
      - 'scripts/generate_image_elements.py'
      - 'tests/test_catalog*.py'
      - 'tests/test_generated*.py'

permissions: {}

jobs:
  catalog:
    name: Validate image catalog
    runs-on: ubuntu-24.04
    timeout-minutes: 10
    permissions:
      contents: read
    steps:
      - name: Checkout
        uses: actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1 # v7.0.1
        with:
          persist-credentials: false

      - name: Install python dependencies
        run: python3 -m pip install --user pyyaml jsonschema

      - name: Records are valid and describe the committed elements
        run: python3 -m unittest discover -s tests -p 'test_catalog*.py' -v

      - name: Generated elements are current
        run: python3 scripts/generate_image_elements.py --check

      - name: Generated elements match their records semantically
        run: python3 -m unittest discover -s tests -p 'test_generated*.py' -v
```

- [ ] **Step 5: Lint the workflow**

Run: `cd /var/home/jorge/src/fsdk-containers && podman run --rm -v "$PWD:/repo:z" -w /repo ghcr.io/projectbluefin/lab-runner:26.08 -c "actionlint .github/workflows/image-catalog.yml"`
Expected: no findings. If `lab-runner` is unavailable locally, run `actionlint` however `docs/skills/ci-tooling/SKILL.md` prescribes.

- [ ] **Step 6: Commit**

```bash
git add .github/workflows/image-catalog.yml Justfile
git commit -m "ci(catalog): gate generated elements against their records

Adds just catalog-write and catalog-check, plus a pull-request gate modelled on
skill-catalog.yml. The gate was verified to fail on a deliberate hand edit
before being committed.

Co-authored-by: Copilot <223556219+Copilot@users.noreply.github.com>"
```

---

### Task 8: Derive the verify gates and smoke test from the record

**Files:**
- Modify: `Justfile:318-500` (the `verify` recipe)
- Create: `scripts/verify_contract.py`
- Test: `tests/test_verify_contract.py`

**Interfaces:**
- Consumes: `catalog.load_record()`, and the record fields `kind`, `size_ceiling_mib`, `gates.require_paths`, `gates.require_binaries`, `smoke`.
- Produces: `verify_contract.gates_for(record) -> dict` and a CLI emitting shell-consumable values, so the `Justfile` stops hard-coding per-image logic.

This is the task that removes the last per-image hand-authored artifact.

- [ ] **Step 1: Write the failing test**

Create `tests/test_verify_contract.py`:

```python
"""Verification gates are derived from the record, not hand-written."""

from pathlib import Path
import sys
import unittest

ROOT = Path(__file__).parents[1]
sys.path.insert(0, str(ROOT / "scripts"))

import catalog  # noqa: E402
import verify_contract as vc  # noqa: E402


class GateDerivationTests(unittest.TestCase):
    def test_distroless_images_forbid_a_shell(self):
        record = catalog.load_record(ROOT / "catalog" / "base.yaml")
        gates = vc.gates_for(record)
        self.assertIn("no-shell", gates["forbid"])

    def test_shell_enabled_images_require_a_shell(self):
        record = catalog.load_record(ROOT / "catalog" / "lab-runner.yaml")
        gates = vc.gates_for(record)
        self.assertNotIn("no-shell", gates["forbid"])
        self.assertIn("bash", gates["require_binaries"])

    def test_size_ceiling_comes_from_the_record(self):
        record = catalog.load_record(ROOT / "catalog" / "python.yaml")
        self.assertEqual(vc.gates_for(record)["max_bytes"], 144 * 1024 * 1024)

    def test_every_published_image_has_a_ceiling(self):
        for record in catalog.load_all():
            with self.subTest(image=record["name"]):
                self.assertGreater(vc.gates_for(record)["max_bytes"], 0)

    def test_smoke_command_uses_the_entrypoint_by_default(self):
        record = catalog.load_record(ROOT / "catalog" / "python.yaml")
        self.assertEqual(vc.smoke_argv(record), ["--version"])

    def test_smoke_command_honours_an_override(self):
        record = catalog.load_record(ROOT / "catalog" / "skopeo.yaml")
        self.assertEqual(
            vc.smoke_argv(record), ["--entrypoint", "/usr/bin/skopeo", "--version"]
        )


if __name__ == "__main__":
    unittest.main()
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd /var/home/jorge/src/fsdk-containers && python3 -m unittest discover -s tests -p 'test_verify_contract.py' -v`
Expected: FAIL with `ModuleNotFoundError: No module named 'verify_contract'`

- [ ] **Step 3: Implement the contract module**

Create `scripts/verify_contract.py`:

```python
#!/usr/bin/env python3
"""Derive an image's verification contract from its catalog record.

The Justfile shells out to this so that adding an image never means editing a
case statement. Emits shell-quoted values for `eval`.

Usage:
    python3 scripts/verify_contract.py <image> --env
"""
from __future__ import annotations

import argparse
import shlex

import catalog

# Paths that must never appear in a distroless rootfs listing. These encode the
# five gates just verify has always applied, plus the leak checks the factory
# design calls for.
FORBIDDEN = {
    "no-shell": r"(^|/)(ba)?sh$",
    "no-sanitizers": r"/lib(asan|tsan|lsan|ubsan|hwasan|gfortran)\.so",
    "no-locale-archive": (
        r"usr/lib(/[^/]*)?/locale/locale-archive$|usr/share/i18n/charmaps/"
        r"|/(localedef|sln|iconvconfig|ldconfig|pcre2test|pcre2grep)$"
        r"|libpcre2-(16|32|posix)\.so"
    ),
    "no-debug-symbols": r"^usr/lib/debug/",
    "no-element-names": r"\.bst($|/)",
}

# Always required of a distroless image, regardless of record contents.
BASELINE_PATHS = [
    "etc/pki/ca-trust/extracted/pem/tls-ca-bundle.pem",
]


def gates_for(record: dict) -> dict:
    """The full verification contract for one image."""
    forbid = dict(FORBIDDEN)
    if record["kind"] == "shell-enabled":
        del forbid["no-shell"]

    require_binaries = list(record.get("gates", {}).get("require_binaries", []))
    if record["kind"] == "shell-enabled" and "bash" not in require_binaries:
        require_binaries.insert(0, "bash")

    return {
        "name": record["name"],
        "kind": record["kind"],
        "max_bytes": record["size_ceiling_mib"] * 1024 * 1024,
        "forbid": forbid,
        "require_paths": list(record.get("gates", {}).get("require_paths", [])),
        "require_binaries": require_binaries,
    }


def smoke_argv(record: dict) -> list[str]:
    """Arguments to append to `podman run --rm <ref>` for the smoke test.

    Returns [] for an image with no smoke block (base, static); the Justfile
    skips the smoke step entirely in that case, matching today's behaviour.
    """
    smoke = record.get("smoke")
    if not smoke:
        return []
    argv: list[str] = []
    override = smoke.get("entrypoint_override")
    if override:
        argv += ["--entrypoint", override[0]]
        argv += override[1:]
    argv += smoke["args"]
    return argv


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("image")
    parser.add_argument("--env", action="store_true", required=True)
    args = parser.parse_args()

    record = catalog.load_record(catalog.CATALOG_DIR / f"{args.image}.yaml")
    gates = gates_for(record)

    print(f"IMG_KIND={shlex.quote(gates['kind'])}")
    print(f"MAX_BYTES={gates['max_bytes']}")
    print(f"FORBID_PATTERNS={shlex.quote(chr(10).join(gates['forbid'].values()))}")
    print(f"FORBID_NAMES={shlex.quote(chr(10).join(gates['forbid'].keys()))}")
    print(
        "REQUIRE_PATHS="
        + shlex.quote(chr(10).join(gates["require_paths"] + BASELINE_PATHS))
    )
    print(f"REQUIRE_BINARIES={shlex.quote(chr(10).join(gates['require_binaries']))}")
    print(f"SMOKE_ARGV={shlex.quote(' '.join(smoke_argv(record)))}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd /var/home/jorge/src/fsdk-containers && python3 -m unittest discover -s tests -p 'test_verify_contract.py' -v`
Expected: PASS, 6 tests.

> **Note on `no-element-names` and `no-debug-symbols`:** these are new gates, not
> ports of existing ones. Running them against today's `base` will FAIL, because
> the image ships `usr/lib/debug/dwz/bootstrap/glibc.bst/...`. That is a real
> finding, not a bug in this task. Land them **disabled** by removing both keys
> from `FORBIDDEN` in this task and add them in the Phase 3 pruning plan, so
> this task keeps its promise of changing no behaviour.

- [ ] **Step 5: Remove the two not-yet-satisfiable gates**

Delete the `"no-debug-symbols"` and `"no-element-names"` entries from
`FORBIDDEN`, and add a comment recording why:

```python
    # NOT YET ENABLED -- these fail against today's images and belong to the
    # Phase 3 pruning plan, which is what makes them satisfiable:
    #   "no-debug-symbols": r"^usr/lib/debug/",
    #   "no-element-names": r"\.bst($|/)",
```

Re-run: `python3 -m unittest discover -s tests -p 'test_verify_contract.py' -v` — still PASS.

- [ ] **Step 6: Rewrite the Justfile verify recipe**

Replace the per-image `case` statement and the `if [ "$IMG" = ... ]` chain in
`verify` with:

```bash
    eval "$(python3 scripts/verify_contract.py "$IMG" --env)"

    SIZE_BYTES=$({{sudo_cmd}} podman image inspect --format '{{"{{.Size}}"}}' "$REF")
    if ! [[ "$SIZE_BYTES" =~ ^[0-9]+$ ]] || [ "$SIZE_BYTES" -gt "$MAX_BYTES" ]; then
        echo "FAIL: $IMG image size ${SIZE_BYTES} bytes exceeds ${MAX_BYTES} bytes" >&2
        exit 1
    fi
    echo "OK: image size ${SIZE_BYTES} bytes (limit ${MAX_BYTES})"

    {{sudo_cmd}} podman create --name verify-base "$REF" /verify-placeholder >/dev/null
    trap '{{sudo_cmd}} podman rm -f verify-base >/dev/null 2>&1 || true' EXIT
    LISTING="$(mktemp)"
    {{sudo_cmd}} podman export verify-base | tar -tf - > "$LISTING"

    # NOTE: these loops use here-strings, not `... | while read`. A piped while
    # loop runs in a subshell, so an `exit 1` inside it exits only the subshell.
    # That construction happens to abort under `set -e` because the pipeline
    # returns non-zero, but a merge gate must not depend on that subtlety. The
    # here-string keeps the loop in the current shell, and the `failed` flag
    # reports every violation instead of only the first.
    failed=0

    while IFS=$'\t' read -r gate pattern; do
        [ -n "$gate" ] || continue
        if grep -qE "$pattern" "$LISTING"; then
            echo "FAIL: gate '$gate' violated — matched $pattern" >&2
            failed=1
        else
            echo "OK: $gate"
        fi
    done <<< "$(paste -d'\t' <(printf '%s\n' "$FORBID_NAMES") <(printf '%s\n' "$FORBID_PATTERNS"))"

    while read -r p; do
        [ -n "$p" ] || continue
        if ! grep -qxF "$p" "$LISTING"; then
            echo "FAIL: required path missing: /$p" >&2
            failed=1
        else
            echo "OK: /$p present"
        fi
    done <<< "$REQUIRE_PATHS"

    while read -r b; do
        [ -n "$b" ] || continue
        if ! grep -qE "(^|/)${b}$" "$LISTING"; then
            echo "FAIL: required binary missing: $b" >&2
            failed=1
        else
            echo "OK: $b present"
        fi
    done <<< "$REQUIRE_BINARIES"

    [ "$failed" -eq 0 ] || { echo "FAIL: $IMG failed one or more gates" >&2; exit 1; }

    echo "==> smoke test (executing binary)"
    # shellcheck disable=SC2086
    if ! {{sudo_cmd}} podman run --rm $SMOKE_ARGV "$REF" >/dev/null 2>&1 \
       && ! {{sudo_cmd}} podman run --rm "$REF" $SMOKE_ARGV >/dev/null 2>&1; then
        echo "FAIL: $IMG smoke test failed" >&2; exit 1
    fi
    echo "OK: $IMG executes successfully"
```

Keep the `lab-runner` `shell_probe` invocation, guarded by `[ "$IMG_KIND" = shell-enabled ]`.

- [ ] **Step 7: Verify all seven images still pass**

```bash
cd /var/home/jorge/src/fsdk-containers
for img in base static skopeo lab-runner python buildah qemu-img; do
  echo "=== $img"
  BUILD_IMAGE_NAME="$img" just build || exit 1
  BUILD_IMAGE_NAME="$img" just verify || exit 1
done
```

Expected: all seven pass, with the same gate names reported as before.

- [ ] **Step 8: Prove the gates still fail when they should**

```bash
cd /var/home/jorge/src/fsdk-containers
python3 - <<'EOF'
import sys; sys.path.insert(0, "scripts")
import catalog, verify_contract as vc
r = catalog.load_record(catalog.CATALOG_DIR / "base.yaml")
r["size_ceiling_mib"] = 1
print("max_bytes:", vc.gates_for(r)["max_bytes"])
assert vc.gates_for(r)["max_bytes"] == 1048576
print("OK: ceiling is honoured from the record")
EOF
```

Expected: `OK: ceiling is honoured from the record`.

- [ ] **Step 9: Commit**

```bash
git add Justfile scripts/verify_contract.py tests/test_verify_contract.py
git commit -m "feat(catalog): derive verify gates and smoke tests from records

Replaces the hand-written per-image case statement and if/elif chain in just
verify. Gate sets follow from kind, required paths and binaries from the
record, and the smoke test from the declared entrypoint. Adding an image no
longer means editing the Justfile.

Two new gates (no-debug-symbols, no-element-names) are written but left
disabled with a comment: they fail against today's images and become
satisfiable only after the Phase 3 pruning work.

Co-authored-by: Copilot <223556219+Copilot@users.noreply.github.com>"
```

---

### Task 9: Prove the economics changed, and document it

**Files:**
- Modify: `docs/skills/add-new-image.md`
- Modify: `docs/SKILL.md` (standing facts)
- Test: `tests/test_catalog_conformance.py`

**Interfaces:**
- Consumes: everything.
- Produces: the acceptance test for the whole plan.

- [ ] **Step 1: Write the acceptance test**

Add to `tests/test_catalog_conformance.py`:

```python
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
            "stack": {
                "base": "base/base-stack.bst",
                "components": ["freedesktop-sdk.bst:components/coreutils.bst"],
            },
        }
        catalog.validate(record)

        for renderer in (gen.render_stack, gen.render_compose, gen.render_oci):
            text = renderer(record)
            self.assertIn("acceptance-probe", text)
            self.assertIn("DO NOT EDIT", text)
            self.assertIsInstance(yaml.safe_load(text), dict)
```

- [ ] **Step 2: Run test to verify it passes**

Run: `cd /var/home/jorge/src/fsdk-containers && python3 -m unittest discover -s tests -p 'test_catalog_conformance.py' -v`
Expected: PASS. If this test needs any change to `scripts/` to pass, the generator still has per-image logic in it — find and remove it.

- [ ] **Step 3: Rewrite the add-new-image skill**

Replace the procedure in `docs/skills/add-new-image.md` with:

```markdown
## Adding an image

1. Write `catalog/<name>.yaml`. That is the whole change.
2. Add `<name>` to `oci_images` and `image_paths` in `elements/targets.json`.
3. Run `just catalog-write` to generate the three BuildStream elements.
4. Run `BUILD_IMAGE_NAME=<name> just build && BUILD_IMAGE_NAME=<name> just verify`.
5. Commit the record, the targets.json entry, and the generated elements together.

**Never hand-edit a generated element.** Every file under `elements/<name>/` and
`elements/oci/<name>.bst` carries a DO-NOT-EDIT header naming its record. A hand
edit is reverted by the next `just catalog-write` and fails the `image-catalog`
pull-request gate in the meantime. Change the record.

If the image needs something the record cannot express, that is a gap in
`catalog/schema.json`. Extend the schema and the generator so the next image
gets it for free — do not work around it with a bespoke element.
```

- [ ] **Step 4: Update the standing facts**

In `docs/SKILL.md`, under "Standing facts", add:

```markdown
- Every OCI image is declared by one record in `catalog/<name>.yaml`. The
  BuildStream elements and the `just verify` contract are generated from it —
  never hand-edit a generated element. `just catalog-write` regenerates,
  `just catalog-check` gates.
```

and in the fast-paths table, change the `add-new-image.md` row's description to
"Add a new distroless image (one catalog record)".

- [ ] **Step 5: Regenerate the skill index**

Run: `cd /var/home/jorge/src/fsdk-containers && python3 scripts/generate_skill_index.py --write`
Expected: `docs/skills/index.json` and `index.md` updated.

- [ ] **Step 6: Run everything**

```bash
cd /var/home/jorge/src/fsdk-containers
python3 -m unittest discover -s tests -v
just catalog-check
just validate
```

Expected: all PASS.

- [ ] **Step 7: Commit**

```bash
git add docs/ tests/test_catalog_conformance.py
git commit -m "docs(catalog): adding an image is adding a record

Rewrites add-new-image.md around the catalog record and adds the plan's
acceptance test: a brand-new record renders all three elements with no change
to any script. If that test ever needs editing to add an image, the generator
has grown per-image logic and the economics have regressed.

Co-authored-by: Copilot <223556219+Copilot@users.noreply.github.com>"
```

---

## Plan validation

The code in this plan was extracted and executed against the real repository on
2026-08-21 before the plan was committed. Verified:

- `catalog/schema.json` parses as valid JSON Schema 2020-12.
- `scripts/catalog.py` loads the `base`, `python` and `lab-runner` records.
- All four negative cases in Task 1 fail as designed: missing required field,
  unknown field, `exclude_omit` without a reason, and `shell_probe` on a
  `distroless` record.
- `render_compose` and `render_stack` reproduce the committed
  `base-runtime.bst`, `base-stack.bst`, `python-runtime.bst` and
  `python-stack.bst` **exactly** on `build-depends`, `depends` and `exclude`.
- `lab-runner`'s declared `exclude_omit: shells` yields precisely the 7-domain
  set its committed compose element already uses.
- The conformance test correctly **failed** against a deliberately incomplete
  `lab-runner` record, listing all 26 missing dependencies. The safety property
  Task 3 depends on is real, not assumed.

## Self-review

**Spec coverage.** This plan implements §5.1 (generated element graph), §5.3
(derived verification), and Phases 1 and 2 of the design's §7. Deliberately
deferred to later plans, each of which needs this one to exist first:

| Design section | Plan |
| --- | --- |
| §7 Phase 0 — make published claims true | Plan 2, independent of this one |
| §5.2 dependency-closure pruning | Plan 3, depends on this |
| §5.4 size ratchet | Plan 4, replaces `size_ceiling_mib` |
| §5.5 uniform provenance, non-root, VEX | Plan 4 |
| §6 catalog growth | Plan 5, gated on the Task 9 acceptance test |

**Placeholder scan.** No "TBD", no "add error handling", no "similar to Task N".
Every code step carries the code. The one deliberate deferral — the two
unsatisfiable gates in Task 8 — is called out explicitly with its reason and the
plan that resolves it, rather than left as a silent gap.

**Type consistency.** `catalog.load_record`, `catalog.load_all`,
`catalog.compose_exclude`, `catalog.CANONICAL_EXCLUDE`, `catalog.CatalogError`
and `catalog.CATALOG_DIR` are defined in Task 1 and used with those exact names
in Tasks 2, 3, 4, 5, 6, 8 and 9. `gen.render_stack`, `gen.render_compose`,
`gen.render_oci`, `gen.check` and the `RENDERERS` registry are consistent across
Tasks 4–6 and 9. `vc.gates_for` and `vc.smoke_argv` are defined in Task 8 and
used only there and in its tests.

**Risk the executing engineer must respect.** Tasks 4, 5 and 6 each overwrite
committed elements. Each has a mandatory "read the whole diff" step and a
build-and-verify step *before* commit, because a wrong record silently changes a
published image. If a diff shows an added or removed dependency or exclude
domain, the correct action is always to fix the record, never to accept the
diff.
