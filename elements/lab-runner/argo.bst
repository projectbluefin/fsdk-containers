kind: manual
description: Fetch the Argo Workflows CLI for lab-runner

build-depends:
  - freedesktop-sdk.bst:components/gzip.bst
  - freedesktop-sdk.bst:bootstrap/coreutils.bst

variables:
  strip-binaries: ""
  # renovate: datasource=github-releases depName=argoproj/argo-workflows
  # Keep the v3 CLI line while the lab workflow contract is checked against
  # the image. The v4 binary added roughly 100 MB uncompressed.
  argo_version: v3.7.17

sources:
  - kind: remote
    (?):
      - arch == "x86_64":
          url: "https://github.com/argoproj/argo-workflows/releases/download/%{argo_version}/argo-linux-amd64.gz"
          ref: c952f442577d7afe4b384700e436abfcf671826eadd0ca25012cf67ae8d8e9a3
      - arch == "aarch64":
          url: "https://github.com/argoproj/argo-workflows/releases/download/%{argo_version}/argo-linux-arm64.gz"
          ref: d651350cf194f2e24c2c080c6149b3a68c541d69b34c616cafe5f2b849738ac8
    filename: argo.gz

config:
  install-commands:
    - |
      gunzip argo.gz
      mkdir -p "%{install-root}/usr/bin"
      cp argo "%{install-root}/usr/bin/argo"
      chmod 755 "%{install-root}/usr/bin/argo"
