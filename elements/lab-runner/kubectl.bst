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
  kubectl_version: v1.36.4

sources:
- kind: remote
  (?):
  - arch == "x86_64":
      url: "k8s-bin:release/%{kubectl_version}/bin/linux/amd64/kubectl"
      ref: 8b8f088da2dab964f853b38464033b1be15ede2839eca751482357c45abdd05a
  - arch == "aarch64":
      url: "k8s-bin:release/%{kubectl_version}/bin/linux/arm64/kubectl"
      ref: 0ecf44450ee6063bf19dd166a103ee6df4a9034455c2abce626e6eea657d73fb
  filename: kubectl

config:
  install-commands:
  - |
    mkdir -p "%{install-root}/usr/bin"
    cp kubectl "%{install-root}/usr/bin/kubectl"
    chmod +x "%{install-root}/usr/bin/kubectl"
