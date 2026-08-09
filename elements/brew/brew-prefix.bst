kind: manual
description: |
  Stage the Homebrew file tree into the linuxbrew prefix without running
  install.sh (which needs network, unavailable in the BST sandbox). Homebrew
  supports an "untar in place" install: the brew.git checkout IS the install.
  Creates the prefix skeleton brew expects on first run; Cellar/opt/lib stay
  empty until the user installs formulas at runtime.

sources:
  - kind: git_repo
    url: github:Homebrew/brew.git
    # renovate: datasource=github-tags depName=Homebrew/brew
    track: 6.0.15
    ref: 7b0f22a4ab77567edef114c8dfc423fb96e2fbaa

depends:
  # coreutils + bash to run the install-commands. FSDK 26.08 removed both from
  # runtime-minimal, so name the shell stack that still provides them.
  - freedesktop-sdk.bst:public-stacks/runtime-gnu.bst
  - freedesktop-sdk.bst:public-stacks/runtime-minimal.bst

variables:
  # Brew ships ruby/bash/perl scripts; nothing to strip and stripping can
  # corrupt the vendored portable-ruby shims.
  strip-binaries: ""

config:
  install-commands:
    - |
      prefix="%{install-root}/home/linuxbrew/.linuxbrew"
      mkdir -p "$prefix/Homebrew" "$prefix/bin" "$prefix/etc" "$prefix/share" \
               "$prefix/Cellar" "$prefix/opt" "$prefix/lib" "$prefix/var/homebrew"
      # The git_repo source is checked out at the build root; it is the brew tree.
      cp -a . "$prefix/Homebrew/"
      # Canonical entrypoint symlink: <prefix>/bin/brew -> <prefix>/Homebrew/bin/brew
      ln -sf ../Homebrew/bin/brew "$prefix/bin/brew"
