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
  argo_version: v4.1.2

sources:
- kind: remote
  (?):
  - arch == "x86_64":
      url: "https://github.com/argoproj/argo-workflows/releases/download/%{argo_version}/argo-linux-amd64.gz"
      ref: 1edee3c25de0129e4d358a87591f04b89b522ceccb11975970d45217a3cd9cdd
  - arch == "aarch64":
      url: "https://github.com/argoproj/argo-workflows/releases/download/%{argo_version}/argo-linux-arm64.gz"
      ref: 3d395d46449cfbd153e459f61c52f87c666a2b207f2a1bbf17856d5b0384df3f
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
