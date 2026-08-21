# Task 9 report

## Acceptance test

Added `AddingAnImageCostsOneFileTests`, which validates an in-memory
`acceptance-probe` record and renders stack, compose, and OCI elements without
any generator change. The targeted conformance run passed:

```
Ran 7 tests in 0.096s
OK
```

This protects the plan's headline economics: adding an image means adding one
catalog record, not adding per-image generator code.

## Documentation

- Rewrote `docs/skills/add-new-image.md` around catalog records, generated
  elements, schema extension, and the load-bearing dependency and keyword
  conventions.
- Added the catalog standing fact and updated the fast-path description in
  `docs/SKILL.md`.
- Regenerated `docs/skills/index.json` and `docs/skills/index.md` with
  `python3 scripts/generate_skill_index.py --write`; generation completed with
  22 skills and validated the index schema.

## Validation

- `just catalog-check`: passed.
- `python3 -m unittest discover -s tests -p 'test_catalog_conformance.py' -v`:
  passed (7 tests).
- `python3 -m unittest discover -s tests -p 'test_*.py' -v`: 37 passed,
  2 pre-existing failures and 1 pre-existing error in
  `tests/test_renovate_atomic.py`, as documented in the task brief.

## Review follow-up

- Strengthened `AddingAnImageCostsOneFileTests` to assert the rendered stack,
  compose, and OCI structures, including ordered dependencies, derived excludes,
  slim/build-oci commands, keywords, and title/description labels.
- Added a name-independence test using the real `python` image name. A temporary
  `if record["name"] == "python": lines.append("# special")` branch caused the
  test to fail; after removing it, the test passed again.
- Corrected `add-new-image.md` to identify exactly the three paths in the
  generator's `RENDERERS` registry and explicitly distinguish hand-authored
  init/support elements.
- Final validation: `just catalog-check` passed; the full unittest discovery
  completed with only the three documented pre-existing
  `test_renovate_atomic.py` failures/errors.
