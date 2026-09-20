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
  kubectl_version: v1.37.0

sources:
- kind: remote
  (?):
  - arch == "x86_64":
      url: "k8s-bin:release/%{kubectl_version}/bin/linux/amd64/kubectl"
      ref: 6129359f4e1f3848a5572ccb0b26cf28b8ca08cef38c95a765b2f64a2c961a2f
  - arch == "aarch64":
      url: "k8s-bin:release/%{kubectl_version}/bin/linux/arm64/kubectl"
      ref: 922df28df248cc00a9e025f947704f1d1482de64ece54cfe57e61f19eaf1eef3
  filename: kubectl

config:
  install-commands:
  - |
    mkdir -p "%{install-root}/usr/bin"
    cp kubectl "%{install-root}/usr/bin/kubectl"
    chmod +x "%{install-root}/usr/bin/kubectl"
