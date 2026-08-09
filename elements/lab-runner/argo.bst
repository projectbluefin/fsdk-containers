kind: manual
description: Fetch the Argo Workflows CLI for lab-runner

build-depends:
  - freedesktop-sdk.bst:public-stacks/runtime-gnu.bst
  - freedesktop-sdk.bst:components/binutils.bst
  - freedesktop-sdk.bst:components/gzip.bst
  - freedesktop-sdk.bst:bootstrap/coreutils.bst

variables:
  # The automatic FSDK stripper is unavailable in manual-element sandboxes.
  # Keep it disabled and strip this upstream binary explicitly below.
  strip-binaries: ""
  # renovate: datasource=github-releases depName=argoproj/argo-workflows
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
      # Decompress to a new file rather than in place: BuildStream may stage
      # the source as a hardlink, and gzip refuses to touch a file with other
      # links ("argo.gz has 1 other link -- file ignored", exit 2).
      gunzip -c argo.gz > argo
      mkdir -p "%{install-root}/usr/bin"
      cp argo "%{install-root}/usr/bin/argo"
      chmod 755 "%{install-root}/usr/bin/argo"
      strip --strip-unneeded "%{install-root}/usr/bin/argo"
