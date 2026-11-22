kind: import
description: |
  Homebrew 7.0.15's matching upstream portable Ruby 4.0.10 bottle. Fetch through
  GHCR's anonymous token exchange before entering the offline build sandbox.
  Digests come from the pinned brew vendor/portable-ruby-{x86_64,arm64}-linux.

sources:
- kind: ghcr_tar
  (?):
  - arch == "x86_64":
      url: https://ghcr.io/v2/homebrew/core/portable-ruby/blobs/sha256:de39ccc6459a91489fbf5e34d4b556e6bfd20a53a0c8104d17ee84e7ab34334f
      ref: de39ccc6459a91489fbf5e34d4b556e6bfd20a53a0c8104d17ee84e7ab34334f
  - arch == "aarch64":
      url: https://ghcr.io/v2/homebrew/core/portable-ruby/blobs/sha256:629b9568a047bffa15ae7ea15544cdbcd2ac63ea136af71777de39fc68dd5598
      ref: 629b9568a047bffa15ae7ea15544cdbcd2ac63ea136af71777de39fc68dd5598

config:
  source: portable-ruby
  target: /portable-ruby
