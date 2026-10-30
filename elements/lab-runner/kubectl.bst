kind: manual
description: Fetch kubectl static binary for lab-runner

build-depends:
  # FSDK 26.08 removed the shell from runtime-minimal; these commands

  # are shell scripts, so declare the interpreter explicitly.

- freedesktop-sdk.bst:public-stacks/runtime-gnu.bst
- freedesktop-sdk.bst:components/make.bst

variables:
  strip-binaries: ""
  # renovate: datasource=github-releases depName=kubernetes/kubernetes
  kubectl_version: v1.37.2

sources:
- kind: remote
  (?):
  - arch == "x86_64":
      url: "k8s-bin:release/%{kubectl_version}/bin/linux/amd64/kubectl"
      ref: c04487523e7aa7d1493f7808174c899db93d7a9cf57531420cd76b9bd415f8f4
  - arch == "aarch64":
      url: "k8s-bin:release/%{kubectl_version}/bin/linux/arm64/kubectl"
      ref: fcc16f63186659d9722014b7e02d5fdd2d4e669cb8c0ab66365d7d3b8ba03509
  filename: kubectl

config:
  install-commands:
  - |
    mkdir -p "%{install-root}/usr/bin"
    cp kubectl "%{install-root}/usr/bin/kubectl"
    chmod +x "%{install-root}/usr/bin/kubectl"
