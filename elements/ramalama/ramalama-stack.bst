kind: stack
description: |
  RamaLama helper runtime stack.

  Uses the upstream RamaLama sdist with verified FSDK Python runtime
  components. `argcomplete` is intentionally omitted: FSDK 25.08 does not ship
  a component for it and RamaLama treats shell completion support as optional.

depends:
  - base/base-stack.bst
  - ramalama/ramalama.bst
  - freedesktop-sdk.bst:components/python3.bst
  - freedesktop-sdk.bst:components/python3-jinja2.bst
  - freedesktop-sdk.bst:components/python3-pyyaml.bst
