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
