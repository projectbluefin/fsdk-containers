# Task 2 report

## Records and sources

| Record field(s) | Committed source |
|---|---|
| `static.description` | `elements/oci/static.bst:43-45` (`org.opencontainers.image.description`); no `entrypoint` or `smoke` because the OCI element has no `Entrypoint` and `Justfile:437-465` has no static smoke arm |
| `static.size_ceiling_mib` | `Justfile:328-334` (`static` case arm) |
| `static.stack` | `elements/static/static-stack.bst:17-26` (`depends`) |
| `python.description`, `entrypoint` | `elements/oci/python.bst:62-67` |
| `python.smoke`, `size_ceiling_mib` | `Justfile:328-334`, `443-447` |
| `python.stack` | `elements/python/python-stack.bst:4-6`; compose exclusions from `elements/python/python-runtime.bst:7-16` |
| `python.slim.extra` | `elements/oci/python.bst:25-43`, copied verbatim after the shared slim command |
| `skopeo.description` | `elements/oci/skopeo.bst:43-46` |
| `skopeo.entrypoint`, `smoke`, `size_ceiling_mib` | `elements/oci/skopeo.bst:43-46`; `Justfile:328-334`, `437-442` |
| `skopeo.stack` | `elements/skopeo/skopeo-stack.bst:6-15`; compose exclusions from `elements/skopeo/skopeo-runtime.bst:7-16` |
| `buildah.description`, `entrypoint` | `elements/oci/buildah.bst:43-48` |
| `buildah.smoke`, `size_ceiling_mib` | `Justfile:328-334`, `448-452` |
| `buildah.stack` | `elements/buildah/buildah-stack.bst:4-17`; compose exclusions from `elements/buildah/buildah-runtime.bst:7-16` |
| `qemu-img.description`, `entrypoint` | `elements/oci/qemu-img.bst:43-47` |
| `qemu-img.smoke`, `size_ceiling_mib` | `Justfile:328-334`, `453-457` |
| `qemu-img.stack` | `elements/qemu-img/qemu-img-stack.bst:4-6`; compose exclusions from `elements/qemu-img/qemu-img-runtime.bst:7-16` |
| `lab-runner.description`, `entrypoint` | `elements/oci/lab-runner.bst:43-46` |
| `lab-runner.smoke`, `size_ceiling_mib` | `Justfile:335-344`, `458-470` |
| `lab-runner.compose.exclude_omit` | `elements/lab-runner/lab-runner-runtime.bst:9-17`; omission reason records the documented shell-enabled exception |
| `lab-runner.stack.components` (17 entries) and `extra_depends` (9 entries) | `elements/lab-runner/lab-runner-stack.bst:8-64` |
| `lab-runner.gates` | `Justfile:360-403`, `468-470` |

## Commands and output

Failing-test TDD step:

```text
python3 -m unittest discover -s tests -p 'test_catalog_conformance.py' -v
...
AssertionError: Items in the first set but not the second:
'static'
'lab-runner'
'skopeo'
'python'
'buildah'
'qemu-img' : published images with no catalog record
...
FAILED (failures=2)
```

Passing validation:

```text
python3 -m unittest discover -s tests -p 'test_catalog*.py' -v
...
Ran 14 tests in 0.039s

OK
```

Additional record-load check confirmed all seven records load, with 17 lab-runner FSDK components and 9 extra dependencies. `git diff --check` passed.

## Surprises or disagreements

- The committed OCI descriptions differ from the prose examples in the brief; records use the committed label values exactly (notably Python, Skopeo, and lab-runner).
- The committed Python slim block contains four additional cleanup paths (`*/config-*` and static archives) beyond the abbreviated brief snippet; the record copies the full committed block byte-for-byte.
- The static stack does not depend on `base/base-stack.bst`; its committed dependencies begin with `runtime-gnu.bst`, so `stack.base` is `null` and those five dependencies are recorded as components.
- The committed lab-runner stack has 17 FSDK components and 9 extra dependencies including `yq.bst`, matching the element rather than the abbreviated comments in the brief.

## Review-finding fixes (2026-08-21)

### Finding 1 — skopeo entrypoint mismatch

Changed `catalog/skopeo.yaml` to omit `entrypoint` and
`smoke.entrypoint_override`, and changed the smoke arguments to
`["skopeo", "--version"]`. This matches the committed OCI element, which has
no `Entrypoint:` key, and preserves the Justfile smoke invocation that passes
`skopeo` as an argument.

Entrypoint audit command and real output:

```text
$ for name in base static python skopeo buildah qemu-img lab-runner; do printf '%s ' "$name"; grep -c 'Entrypoint:' "elements/oci/$name.bst"; done
base 0
static 0
python 1
skopeo 0
buildah 1
qemu-img 1
lab-runner 1
```

The seven records now agree exactly with those committed element counts:
`python`, `buildah`, `qemu-img`, and `lab-runner` declare entrypoints; `base`,
`static`, and `skopeo` omit them.

### Finding 2 — missing Artifact Hub keywords

Added the `keywords` property to `catalog/schema.json` and transcribed it into
all seven records from each committed OCI element. The values used were:

- `base`: `distroless,freedesktop-sdk,bluefin`
- `static`: `distroless,freedesktop-sdk,bluefin,static`
- `python`: `distroless,freedesktop-sdk,bluefin,python`
- `skopeo`: `distroless,freedesktop-sdk,bluefin,skopeo`
- `buildah`: `distroless,freedesktop-sdk,bluefin,buildah`
- `qemu-img`: `distroless,freedesktop-sdk,bluefin,qemu-img`
- `lab-runner`: `freedesktop-sdk,bluefin,ci`

Throwaway verification script command and real output:

```text
$ python3 verify_catalog_records.py
base: PASS keywords=PASS entrypoint=PASS
buildah: PASS keywords=PASS entrypoint=PASS
lab-runner: PASS keywords=PASS entrypoint=PASS
python: PASS keywords=PASS entrypoint=PASS
qemu-img: PASS keywords=PASS entrypoint=PASS
skopeo: PASS keywords=PASS entrypoint=PASS
static: PASS keywords=PASS entrypoint=PASS
$ rm verify_catalog_records.py
```

The script compared every record's `keywords` against the
`io.artifacthub.package.keywords` label and compared entrypoint-field presence
against `Entrypoint:` presence in the corresponding committed element. All
seven passed; no table disagreement was found.

### Required test suite

```text
$ python3 -m unittest discover -s tests -p 'test_catalog*.py' -v
[...]
----------------------------------------------------------------------
Ran 14 tests in 0.041s

OK
```

Additional validation:

```text
$ git diff --check
# no output (passed)
```

Full test output (rerun for the report):

```text
$ python3 -m unittest discover -s tests -p 'test_catalog*.py' -v
test_every_published_image_has_a_record (test_catalog_conformance.CatalogCoverageTests.test_every_published_image_has_a_record) ... ok
test_every_record_is_a_published_image (test_catalog_conformance.CatalogCoverageTests.test_every_record_is_a_published_image) ... ok
test_exactly_one_shell_enabled_image (test_catalog_conformance.CatalogCoverageTests.test_exactly_one_shell_enabled_image) ... ok
test_a_record_may_omit_entrypoint_and_smoke (test_catalog_schema.SchemaTests.test_a_record_may_omit_entrypoint_and_smoke)
base and static have neither today; the schema must not force them. ... ok
test_an_empty_shell_probe_is_also_rejected (test_catalog_schema.SchemaTests.test_an_empty_shell_probe_is_also_rejected)
Presence, not truthiness. An empty string is still a shell probe. ... ok
test_base_record_is_valid (test_catalog_schema.SchemaTests.test_base_record_is_valid) ... ok
test_compose_exclude_is_canonical_by_default (test_catalog_schema.SchemaTests.test_compose_exclude_is_canonical_by_default) ... ok
test_exclude_omit_requires_a_reason (test_catalog_schema.SchemaTests.test_exclude_omit_requires_a_reason) ... ok
test_missing_required_field_is_rejected (test_catalog_schema.SchemaTests.test_missing_required_field_is_rejected) ... ok
test_name_must_match_filename (test_catalog_schema.SchemaTests.test_name_must_match_filename) ... ok
test_shell_probe_is_allowed_on_a_shell_enabled_record (test_catalog_schema.SchemaTests.test_shell_probe_is_allowed_on_a_shell_enabled_record) ... ok
test_shell_probe_is_rejected_on_a_distroless_record (test_catalog_schema.SchemaTests.test_shell_probe_is_rejected_on_a_distroless_record) ... ok
test_the_baseline_fixture_is_actually_valid (test_catalog_schema.SchemaTests.test_the_baseline_fixture_is_actually_valid)
Guards every negative test below: if this fails, they prove nothing. ... ok
test_unknown_field_is_rejected (test_catalog_schema.SchemaTests.test_unknown_field_is_rejected) ... ok

----------------------------------------------------------------------
Ran 14 tests in 0.042s

OK
```
