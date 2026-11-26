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
  kubectl_version: v1.37.3

sources:
- kind: remote
  (?):
  - arch == "x86_64":
      url: "k8s-bin:release/%{kubectl_version}/bin/linux/amd64/kubectl"
      ref: 9a1b55af2795b25dd288dbef62387db9b5530087ab918d28c6ad067f2e3cb07c
  - arch == "aarch64":
      url: "k8s-bin:release/%{kubectl_version}/bin/linux/arm64/kubectl"
      ref: da160b41491cc5c5e575d78bb665810fb900f70fad666d834094b24ec56d304f
  filename: kubectl

config:
  install-commands:
  - |
    mkdir -p "%{install-root}/usr/bin"
    cp kubectl "%{install-root}/usr/bin/kubectl"
    chmod +x "%{install-root}/usr/bin/kubectl"
