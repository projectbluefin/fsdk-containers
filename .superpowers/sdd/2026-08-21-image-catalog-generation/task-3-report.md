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
