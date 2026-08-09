kind: stack
description: |
  Lab runner: shell-enabled utility container for CI workflow steps.
  Replaces cgr.dev/chainguard/wolfi-base + apk add in Argo workflow
  templates. Shell is intentionally kept — this is not a distroless
  image. All tools are FSDK-built; no runtime package manager.

depends:
  - base/base-stack.bst
  - freedesktop-sdk.bst:components/curl.bst
  - freedesktop-sdk.bst:components/git.bst
  - freedesktop-sdk.bst:components/jq.bst
  - freedesktop-sdk.bst:components/python3.bst
  - freedesktop-sdk.bst:components/openssh.bst
  # Neither the shipped python3 nor the shell can parse YAML without these:
  # python3-pyyaml covers `import yaml`, and yq covers shell pipelines
  # (GitHub Actions workflows, skill frontmatter, Kubernetes manifests). A
  # contributor agent assigned to edit YAML with only what this image ships
  # otherwise hits `ModuleNotFoundError: No module named 'yaml'` and
  # `yq: command not found`.
  - freedesktop-sdk.bst:components/python3-pyyaml.bst
  - lab-runner/yq.bst
  # Standard POSIX/GNU userland beyond coreutils. A shell-enabled CI container
  # that answers `which`, `xargs`, `awk`, `ps`, `tar`, `diff` and `patch` with
  # exit 127 forces every consumer to either hand-roll a replacement or work
  # around the gap; both cost more than carrying the real GNU tools.
  - freedesktop-sdk.bst:components/diffutils.bst
  - freedesktop-sdk.bst:components/file.bst
  - freedesktop-sdk.bst:components/findutils.bst
  - freedesktop-sdk.bst:components/gawk.bst
  # GNU tar does not decompress gzip itself — it execs the `gzip` binary, so
  # without this both `tar -xzf` and plain `tar -xf` fail on a .tar.gz with
  # "gzip: Cannot exec: No such file or directory" (#87). xz and zstd are
  # separate binaries and were already fine; zstd is built without zlib here,
  # so `zstd --format=gzip` is not a substitute. Several lab-runner elements
  # (actionlint, just, argo) already build-depend on gzip to unpack their own
  # release tarballs, which is why the gap never showed up at build time.
  - freedesktop-sdk.bst:components/gzip.bst
  - freedesktop-sdk.bst:components/less.bst
  - freedesktop-sdk.bst:components/patch.bst
  - freedesktop-sdk.bst:components/procps.bst
  - freedesktop-sdk.bst:components/tar.bst
  - freedesktop-sdk.bst:components/which.bst
  # Contributor / CI linters
  - lab-runner/shellcheck.bst
  - lab-runner/hadolint.bst
  - lab-runner/actionlint.bst
  - lab-runner/argo.bst
  - lab-runner/just.bst
  - lab-runner/kubectl.bst
  - lab-runner/nginx.bst
