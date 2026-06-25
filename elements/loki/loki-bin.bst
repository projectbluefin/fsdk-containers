kind: import
description: |
  Pre-built Loki static binary from the official GitHub release.
  Loki is compiled with CGO_ENABLED=0 — pure static, no glibc dependency.
  Selects amd64 or arm64 zip based on target_arch.
  Version: v3.7.3

sources:
- kind: zip
  url: https://github.com/grafana/loki/releases/download/v3.7.3/loki-linux-amd64.zip
  ref: 'cd28bc1e12f005c39fdf3c49e6be793206749b0f16db5eed742727b484a027ae'
  base-dir: ''

(?):
- arch == 'aarch64':
    sources:
    - kind: zip
      url: https://github.com/grafana/loki/releases/download/v3.7.3/loki-linux-arm64.zip
      ref: 'd5bb2ca26f640fd66141654ae85521b12085e12a0d4fe0977917bef8e5c41f82'
      base-dir: ''
