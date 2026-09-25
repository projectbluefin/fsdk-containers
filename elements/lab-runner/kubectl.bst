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
  kubectl_version: v1.37.1

sources:
- kind: remote
  (?):
  - arch == "x86_64":
      url: "k8s-bin:release/%{kubectl_version}/bin/linux/amd64/kubectl"
      ref: 65691ff77eb6fa44c908b77a1082c9f092c3b9733b5cefabec0d1104890e21a8
  - arch == "aarch64":
      url: "k8s-bin:release/%{kubectl_version}/bin/linux/arm64/kubectl"
      ref: ff749f4b78d9c4f1ec87307df9b50119ed819e2094aa9810cb9acffc3286c8c7
  filename: kubectl

config:
  install-commands:
  - |
    mkdir -p "%{install-root}/usr/bin"
    cp kubectl "%{install-root}/usr/bin/kubectl"
    chmod +x "%{install-root}/usr/bin/kubectl"
