kind: manual
description: Install the upstream RamaLama Python distribution from the verified PyPI sdist.

sources:
  - kind: tar
    # renovate: datasource=pypi depName=ramalama
    url: https://files.pythonhosted.org/packages/75/3b/840e5bd99acfbb5bf6e7072e2faf2e161fbbebb9e2218b4abb34ab16ace1/ramalama-0.23.0.tar.gz
    ref: dc02b82e46ddd682cb1019c5d474c1caf48a38ca13798d6e92aa3b779e04ef04

build-depends:
  - freedesktop-sdk.bst:components/python3.bst
  - freedesktop-sdk.bst:components/python3-build.bst
  - freedesktop-sdk.bst:components/python3-installer.bst
  - freedesktop-sdk.bst:components/python3-setuptools.bst
  - freedesktop-sdk.bst:components/python3-wheel.bst

variables:
  strip-binaries: ""

config:
  build-commands:
    - |
      python3 -m build --wheel --no-isolation

  install-commands:
    - |
      python3 -m installer --destdir "%{install-root}" --prefix /usr dist/*.whl
