# Task 3 report

## Initial conformance run

The newly added conformance tests passed immediately; no record mismatches were
found:

```
Ran 6 tests in 0.092s

OK
```

## Passing run

The required catalog test discovery also passed:

```
Ran 17 tests in 0.101s

OK
```

## Mismatches

No stack dependency, compose exclude, or `slim.extra` mismatches were found.
No record was changed, and no deviation was added.

## Mutation check

I temporarily changed `catalog/python.yaml` to declare
`freedesktop-sdk.bst:components/not-python.bst`, then restored the record. The
stack conformance test failed for `python` and named the differing dependency:

```
FAIL: test_stack_depends_match_the_record (...) (image='python')
AssertionError: Lists differ:
['base/base-stack.bst', 'freedesktop-sdk.bst:components/python3.bst']
!= ['base/base-stack.bst', 'freedesktop-sdk.bst:components/not-python.bst']
```

This confirms the test detects a lying record.

## Scope and branch checks

`git status --short elements/` produced empty output. HEAD is on
`feat/catalog-generation`.

## Review finding fix

Updated `tests/test_catalog_conformance.py` so `slim.extra` commands are taken
from the structural `commands[1:-2]` position after asserting the OCI command
shape. Comparison now omits `.strip()` and is byte-for-byte. No catalog or
element files were changed.

### Mutation checks

Each mutation was restored with a trap; after every check, `git status --short`
contained only the intended test modification (and `git status --short elements/`
was empty).

1. **Lying stack dependency** (`jq.bst` → `not-a-real-component.bst`):

```
FAIL: test_stack_depends_match_the_record (test_catalog_conformance.RecordsDescribeRealityTests.test_stack_depends_match_the_record) (image='lab-runner')
AssertionError: Lists differ:
  ...
-  'freedesktop-sdk.bst:components/jq.bst',
+  'freedesktop-sdk.bst:components/not-a-real-component.bst',
  ...
: lab-runner-stack.bst depends do not match catalog/lab-runner.yaml

Ran 1 test in 0.018s

FAILED (failures=1)
```

2. **Missing `compose.exclude_omit`**:

```
FAIL: test_compose_exclude_matches_the_record (...) (image='lab-runner')
AssertionError: Lists differ: [..., 'static-blocklist', ...] != [..., 'shells', 'static-blocklist', ...]
: lab-runner-runtime.bst exclude set does not match catalog/lab-runner.yaml; declare the difference in compose.exclude_omit with a reason

Ran 6 tests in 0.090s

FAILED (failures=1)
```

3. **Missing `slim.extra`** (full output):

```
FAIL: test_slim_extra_matches_the_committed_oci_element (...) (image='python')
AssertionError: Lists differ: ['set -eu\nL=/layer\nrm -rf "$L"/...\n'] != []

First list contains 1 additional element:
'set -eu\nL=/layer\nrm -rf "$L"/usr/lib/python*/test \\\n       "$L"/usr/lib/python*/*/test \\\n       "$L"/usr/lib/python*/*/tests \\\n       "$L"/usr/lib/python*/ensurepip \\\n       "$L"/usr/lib/python*/idlelib \\\n       "$L"/usr/lib/python*/tkinter \\\n       "$L"/usr/lib/python*/turtledemo \\\n       "$L"/usr/lib/python*/turtle.py \\\n       "$L"/usr/lib/python*/lib2to3 \\\n       "$L"/usr/lib/python*/pydoc_data \\\n       "$L"/usr/lib/python*/__phello__ \\\n       "$L"/usr/lib/python*/config-* \\\n       "$L"/usr/lib/python*/*/config-* \\\n       "$L"/usr/lib/python*/*.a \\\n       "$L"/usr/lib/python*/*/*.a\n'

+ []
- ['set -eu\n', 'L=/layer\n', 'rm -rf ...']
: catalog/python.yaml slim.extra is not byte-equal to the extra commands in oci/python.bst

Ran 1 test in 0.024s

FAILED (failures=1)
```

4. **Leading whitespace in the first `slim.extra` line** (valid YAML block
scalar mutation):

```
FAIL: test_slim_extra_matches_the_committed_oci_element (...) (image='python')
AssertionError: Lists differ: ['set -eu\nL=/layer\n...'] != [' set -eu\nL=/layer\n...']
: catalog/python.yaml slim.extra is not byte-equal to the extra commands in oci/python.bst

Ran 6 tests in 0.091s

FAILED (failures=1)
```

### Final required run

```
$ python3 -m unittest discover -s tests -p 'test_catalog*.py' -v
Ran 17 tests in 0.096s

OK
```
