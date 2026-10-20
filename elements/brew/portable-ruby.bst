kind: import
description: |
  Homebrew 7.0.10's matching upstream portable Ruby 4.0.7_1 bottle. Fetch through
  GHCR's anonymous token exchange before entering the offline build sandbox.
  Digests come from the pinned brew vendor/portable-ruby-{x86_64,arm64}-linux.

sources:
- kind: ghcr_tar
  (?):
  - arch == "x86_64":
      url: https://ghcr.io/v2/homebrew/core/portable-ruby/blobs/sha256:1f78c64df16fc4715452d059c3a8482ba12b683cc582a2e07e19bddaea88d4f7
      ref: 1f78c64df16fc4715452d059c3a8482ba12b683cc582a2e07e19bddaea88d4f7
  - arch == "aarch64":
      url: https://ghcr.io/v2/homebrew/core/portable-ruby/blobs/sha256:7a43dce308d310788045ea32b5476ad618d0e92e72b540741b83a73717479dc4
      ref: 7a43dce308d310788045ea32b5476ad618d0e92e72b540741b83a73717479dc4

config:
  source: portable-ruby
  target: /portable-ruby
