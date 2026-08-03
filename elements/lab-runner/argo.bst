kind: manual
description: Fetch the Argo Workflows CLI for lab-runner

build-depends:
  - freedesktop-sdk.bst:components/gzip.bst
  - freedesktop-sdk.bst:bootstrap/coreutils.bst

variables:
  strip-binaries: ""
  # BuildStream source is intentionally not Renovate-managed: the release artifact has no authoritative checksum manifest.
  # depName=argoproj/argo-workflows
  argo_version: v4.0.8

sources:
  - kind: remote
    (?):
      - arch == "x86_64":
          url: "https://github.com/argoproj/argo-workflows/releases/download/%{argo_version}/argo-linux-amd64.gz"
          ref: d92ea4cb4afbca3d6eeb68988cfc4d3220d91831ce3689cc12312c9babcf4003
      - arch == "aarch64":
          url: "https://github.com/argoproj/argo-workflows/releases/download/%{argo_version}/argo-linux-arm64.gz"
          ref: b54757a0060e3b6529e06de3d2a5a7fec82dc3e2fd436f78c712340101e4981a
    filename: argo.gz

config:
  install-commands:
    - |
      gunzip argo.gz
      mkdir -p "%{install-root}/usr/bin"
      cp argo "%{install-root}/usr/bin/argo"
      chmod 755 "%{install-root}/usr/bin/argo"
