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
  kubectl_version: v1.36.3

sources:
  - kind: remote
    (?):
      - arch == "x86_64":
          url: "k8s-bin:release/%{kubectl_version}/bin/linux/amd64/kubectl"
          ref: ebbd080e7c2e275093b55915722043257eb24004363e20acb3c4d71919f88336
      - arch == "aarch64":
          url: "k8s-bin:release/%{kubectl_version}/bin/linux/arm64/kubectl"
          ref: 3d86f24401c41ae5a46ac50eef8865fe891d3647d324a0836f6c63757a126e62
    filename: kubectl

config:
  install-commands:
    - |
      mkdir -p "%{install-root}/usr/bin"
      cp kubectl "%{install-root}/usr/bin/kubectl"
      chmod +x "%{install-root}/usr/bin/kubectl"
