kind: manual
description: Fetch kubectl static binary for lab-runner

build-depends:
  - freedesktop-sdk.bst:components/make.bst

variables:
  # renovate: datasource=github-releases depName=kubernetes/kubernetes
  kubectl_version: v1.30.2

sources:
  - kind: remote
    (?):
      - arch == "x86_64":
          url: "k8s-bin:release/%{kubectl_version}/bin/linux/amd64/kubectl"
          ref: c6e9c45ce3f82c90663e3c30db3b27c167e8b19d83ed4048b61c1013f6a7c66e
      - arch == "aarch64":
          url: "k8s-bin:release/%{kubectl_version}/bin/linux/arm64/kubectl"
          ref: 56becf07105fbacd2b70f87f3f696cfbed226cb48d6d89ed7f65ba4acae3f2f8
    filename: kubectl

config:
  install-commands:
    - |
      mkdir -p "%{install-root}/usr/bin"
      cp kubectl "%{install-root}/usr/bin/kubectl"
      chmod +x "%{install-root}/usr/bin/kubectl"
