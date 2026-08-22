# Task 7 report

## Drift proofs

Each proof appended `# hand edit`, ran `just catalog-check`, recorded the
failure, and restored the file with `git checkout -- <path>`.

```text
STALE: elements/python/python-runtime.bst does not match its catalog record. Run: just catalog-write
error: recipe `catalog-check` failed on line 225 with exit code 1
exit=1
```

```text
STALE: elements/python/python-stack.bst does not match its catalog record. Run: just catalog-write
error: recipe `catalog-check` failed on line 225 with exit code 1
exit=1
```

```text
STALE: elements/oci/python.bst does not match its catalog record. Run: just catalog-write
error: recipe `catalog-check` failed on line 225 with exit code 1
exit=1
```

After restoration, `git status --short` showed only the intended `Justfile`
edit and new workflow/report files; no proof edits remained. A final
`just catalog-check` passed.

## Python dependencies

The existing workflows contain no Python dependency installation pattern for
PyYAML or jsonschema. Both packages were already available locally; the
workflow uses the brief's explicit `python3 -m pip install --user pyyaml
jsonschema` so the runner is self-contained and deterministic.

## Workflow lint

`actionlint .github/workflows/image-catalog.yml` completed successfully with no
findings.

## Final validation

`just catalog-check`: passed (17 catalog tests and 9 generated-element tests).

`python3 -m unittest discover -s tests -p 'test_*.py' -v`: 26 passed; 3
pre-existing failures in `test_renovate_atomic.py`, as expected.
