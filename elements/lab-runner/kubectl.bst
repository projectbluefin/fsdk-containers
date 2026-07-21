kind: manual
description: Fetch kubectl static binary for lab-runner

build-depends:
  - freedesktop-sdk.bst:components/make.bst

variables:
  strip-binaries: ""
  # renovate: datasource=github-releases depName=kubernetes/kubernetes
  kubectl_version: v1.36.2

sources:
  - kind: remote
    (?):
      - arch == "x86_64":
          url: "k8s-bin:release/%{kubectl_version}/bin/linux/amd64/kubectl"
          ref: 1e9045ec32bea85da43de85f0065358529ea7c7a152eca78154fba5b58c27d82
      - arch == "aarch64":
          url: "k8s-bin:release/%{kubectl_version}/bin/linux/arm64/kubectl"
          ref: c957eb8c4bea27a3bb35b269edd9082e27f027f7b76b20b5bf4afebc726c6d3e
    filename: kubectl

config:
  install-commands:
    - |
      mkdir -p "%{install-root}/usr/bin"
      cp kubectl "%{install-root}/usr/bin/kubectl"
      chmod +x "%{install-root}/usr/bin/kubectl"
