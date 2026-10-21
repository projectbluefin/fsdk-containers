kind: import
description: |
  Homebrew 7.0.9's matching upstream portable Ruby 4.0.7 bottle. Fetch through
  GHCR's anonymous token exchange before entering the offline build sandbox.
  Digests come from the pinned brew vendor/portable-ruby-{x86_64,arm64}-linux.

sources:
- kind: ghcr_tar
  (?):
  - arch == "x86_64":
      url: https://ghcr.io/v2/homebrew/core/portable-ruby/blobs/sha256:bf2a9bf102694d40084ed436b06a1566dded60a519f4d1879c90c81046e11081
      ref: bf2a9bf102694d40084ed436b06a1566dded60a519f4d1879c90c81046e11081
  - arch == "aarch64":
      url: https://ghcr.io/v2/homebrew/core/portable-ruby/blobs/sha256:c9b75dd6bd9578921f3ce739dacae8866698c3399c0f83574a5d5fadda2aab2d
      ref: c9b75dd6bd9578921f3ce739dacae8866698c3399c0f83574a5d5fadda2aab2d

config:
  source: portable-ruby
  target: /portable-ruby
