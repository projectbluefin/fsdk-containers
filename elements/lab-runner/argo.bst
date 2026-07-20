kind: manual
description: Fetch the Argo Workflows CLI for lab-runner

build-depends:
  - freedesktop-sdk.bst:components/gzip.bst
  - freedesktop-sdk.bst:bootstrap/coreutils.bst

variables:
  strip-binaries: ""
  # renovate: datasource=github-releases depName=argoproj/argo-workflows
  argo_version: v4.0.7

sources:
  - kind: remote
    (?):
      - arch == "x86_64":
          url: "https://github.com/argoproj/argo-workflows/releases/download/%{argo_version}/argo-linux-amd64.gz"
          ref: 1bb635c42d0bedf9fc6ae105962638c04244b4ff26b96069a06a6a01929add97
      - arch == "aarch64":
          url: "https://github.com/argoproj/argo-workflows/releases/download/%{argo_version}/argo-linux-arm64.gz"
          ref: eb1fbccc7a2de9468805b112da69c9af83217597fcdc31ea077f696494cd23ed
    filename: argo.gz

config:
  install-commands:
    - |
      gunzip argo.gz
      mkdir -p "%{install-root}/usr/bin"
      cp argo "%{install-root}/usr/bin/argo"
      chmod 755 "%{install-root}/usr/bin/argo"
