kind: stack
description: FSDK foomatic-db for printer applications, built against the printing stack's CUPS.

# freedesktop-sdk's components/foomatic-db.bst build-depends on the patched
# CUPS, so its cache key moved and no remote serves it. It is bundled into
# printing-base-devel next to printing/base.bst, but deliberately not part of
# base.bst: only the applications that ship PPDs (ghostscript, ps) depend on
# it, and base.bst is in every consumer's closure.
depends:
- freedesktop-sdk.bst:components/foomatic-db.bst
