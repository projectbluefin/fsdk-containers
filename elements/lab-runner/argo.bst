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
  argo_version: v4.1.3

sources:
- kind: remote
  (?):
  - arch == "x86_64":
      url: "https://github.com/argoproj/argo-workflows/releases/download/%{argo_version}/argo-linux-amd64.gz"
      ref: f3cf6ae424e9d2b3139efd29f673e7efc47a68881352a26a4122f72c4fc0efd4
  - arch == "aarch64":
      url: "https://github.com/argoproj/argo-workflows/releases/download/%{argo_version}/argo-linux-arm64.gz"
      ref: 0d10a03a490bcfb2f5acb2bb6236357b2132159f5b37aa2ea54d6febb2c5ff57
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
