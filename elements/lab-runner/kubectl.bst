kind: manual
description: Fetch kubectl static binary for lab-runner

variables:
  # renovate: datasource=github-releases depName=kubernetes/kubernetes
  kubectl_version: v1.30.2

sources:
  - kind: remote
    (?):
      - arch == "x86_64":
          url: "k8s-bin:release/%{kubectl_version}/bin/linux/amd64/kubectl"
          ref: c14dea3e76dea3d930034f1af090b2e4cf0ed5eb24d452354011095890c079e9
      - arch == "aarch64":
          url: "k8s-bin:release/%{kubectl_version}/bin/linux/arm64/kubectl"
          ref: 70a4ddf9ac5013cb8efa9946ce1e2075a90ab5a509314628d9e2c87dd1287094
    filename: kubectl

config:
  install-commands:
    - |
      mkdir -p "%{install-root}/usr/bin"
      cp kubectl "%{install-root}/usr/bin/kubectl"
      chmod +x "%{install-root}/usr/bin/kubectl"
