kind: import
description: |
  Homebrew 7.0.11's matching upstream portable Ruby 4.0.9 bottle. Fetch through
  GHCR's anonymous token exchange before entering the offline build sandbox.
  Digests come from the pinned brew vendor/portable-ruby-{x86_64,arm64}-linux.

sources:
- kind: ghcr_tar
  (?):
  - arch == "x86_64":
      url: https://ghcr.io/v2/homebrew/core/portable-ruby/blobs/sha256:20d7b22eba004e0518932ce7f8a271c16b1a9da91b81f696c735d14d817a2c07
      ref: 20d7b22eba004e0518932ce7f8a271c16b1a9da91b81f696c735d14d817a2c07
  - arch == "aarch64":
      url: https://ghcr.io/v2/homebrew/core/portable-ruby/blobs/sha256:346f2c71db33cdf4c64c68954f4e1134fbf63cc0d1a5885cfdf94b881f5ec53b
      ref: 346f2c71db33cdf4c64c68954f4e1134fbf63cc0d1a5885cfdf94b881f5ec53b

config:
  source: portable-ruby
  target: /portable-ruby
