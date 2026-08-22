kind: stack
description: |
  PostgreSQL runtime stack (built on base stack).

  Wave 0 feasibility spike (#146), deliberately INERT: no OCI element,
  no targets.json entry, nothing published. The four spike answers
  (mechanism / dependency set / resolves+builds / version+ref) are
  recorded in postgres/postgres.bst's description. Composes from
  FSDK components/* via base-stack — never platform.bst; no x86_64_v3.

depends:
  - base/base-stack.bst
  - postgres/postgres.bst
