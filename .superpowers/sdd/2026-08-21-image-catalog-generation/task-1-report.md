# Task 1 report

## Created
- `catalog/schema.json`
- `catalog/base.yaml`
- `scripts/catalog.py`
- `tests/test_catalog_schema.py`
- `docs/skills/add-new-image.md` updated with a catalog-first note

## Validation

Failing run:

```bash
cd /var/home/jorge/src/fsdk-containers/.worktrees/catalog && python3 -m unittest tests.test_catalog_schema -v
```

Output:

```text
test_catalog_schema (unittest.loader._FailedTest.test_catalog_schema) ... ERROR

======================================================================
ERROR: test_catalog_schema (unittest.loader._FailedTest.test_catalog_schema)
----------------------------------------------------------------------
ImportError: Failed to import test module: test_catalog_schema
Traceback (most recent call last):
  File "/usr/lib/python3.13/unittest/loader.py", line 137, in loadTestsFromName
    module = __import__(module_name)
ModuleNotFoundError: No module named 'tests.test_catalog_schema'


----------------------------------------------------------------------
Ran 1 test in 0.000s

FAILED (errors=1)
```

Passing run:

```bash
cd /var/home/jorge/src/fsdk-containers/.worktrees/catalog && python3 -m unittest discover -s tests -p test_catalog_schema.py -v
```

Output:

```text
test_base_record_is_valid (test_catalog_schema.SchemaTests.test_base_record_is_valid) ... ok
test_compose_exclude_is_canonical_by_default (test_catalog_schema.SchemaTests.test_compose_exclude_is_canonical_by_default) ... ok
test_exclude_omit_requires_a_reason (test_catalog_schema.SchemaTests.test_exclude_omit_requires_a_reason) ... ok
test_missing_required_field_is_rejected (test_catalog_schema.SchemaTests.test_missing_required_field_is_rejected) ... ok
test_name_must_match_filename (test_catalog_schema.SchemaTests.test_name_must_match_filename) ... ok
test_unknown_field_is_rejected (test_catalog_schema.SchemaTests.test_unknown_field_is_rejected) ... ok

----------------------------------------------------------------------
Ran 6 tests in 0.007s

OK
```

## Deviation
- The brief expected the exact `python3 -m unittest tests.test_catalog_schema -v` command to fail with `No module named 'catalog'`. In this environment, a user-site `tests` package shadows the repo's namespace package, so the direct command fails earlier with `No module named 'tests.test_catalog_schema'`.
- I did not add `tests/__init__.py` because the brief explicitly said not to.

## Surprise
- The machine already has a `tests` package installed in user site-packages.

## Commit
- `64bddc4`

## Fix report append

### Finding 1 — `shell_probe` guard checks presence, not truthiness
- Changed: `scripts/catalog.py` now rejects any record whose `smoke` mapping contains `shell_probe` unless `kind: shell-enabled`.
- Test coverage: `test_shell_probe_is_rejected_on_a_distroless_record`, `test_an_empty_shell_probe_is_also_rejected`, `test_shell_probe_is_allowed_on_a_shell_enabled_record`.
- Command run: `python3 -m unittest discover -s tests -p 'test_catalog*.py' -v`
- Real output: 11 tests ran and passed; the suite includes the three shell-probe tests above.

### Finding 2 — negative tests were vacuous
- Changed: replaced the old fixtures with `valid_record(**overrides)`, added `test_the_baseline_fixture_is_actually_valid`, and made each negative test vary one thing only.
- Test coverage: `test_the_baseline_fixture_is_actually_valid`, `test_unknown_field_is_rejected`, `test_exclude_omit_requires_a_reason`.
- Mutation check command: `python3 - <<'PY' ...` mutating `"additionalProperties": false` to `true`, running the schema suite, restoring the schema, and rerunning it.
- Mutation result: with the mutation, `test_unknown_field_is_rejected` FAILED (`AssertionError: CatalogError not raised`); after restore, the same suite passed again.
- Exact observed output:
  - Mutated: `Ran 11 tests ... FAILED (failures=1)`
  - Restored: `Ran 11 tests ... OK`

### Finding 3 — `catalog/base.yaml` must not invent an entrypoint
- Changed: removed the fabricated `entrypoint` and `smoke` blocks from `catalog/base.yaml`.
- Test coverage: `test_a_record_may_omit_entrypoint_and_smoke` plus `test_base_record_is_valid`.
- Command run: `python3 -m unittest discover -s tests -p 'test_catalog*.py' -v`
- Real output: the suite passed with `test_a_record_may_omit_entrypoint_and_smoke ... ok` and `test_base_record_is_valid ... ok`.

### Finding 4 — revert scope creep in `docs/skills/add-new-image.md`
- Changed: reverted the earlier doc edit completely, including restoring `last_updated: 2026-08-20` and removing the catalog-first addition.
- Test coverage: none; this was a scope correction only.
- Command run: `git show 64bddc4^:docs/skills/add-new-image.md > docs/skills/add-new-image.md`
- Real output: file restored from the parent commit with no extra edits left in that section.

### Full verification
- Command run: `python3 -m unittest discover -s tests -p 'test_catalog*.py' -v`
- Real output: `Ran 11 tests in 0.007s` and `OK`.
- Commit: `3a3f2727e88123dfa08beefaae4db70f4b801edd`
