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

build-depends:
  # coreutils + bash to run the install-commands. FSDK 26.08 removed both from
  # runtime-minimal, so name the shell stack that still provides them.
  #
  # These are BUILD dependencies, not runtime ones: they exist to execute the
  # install-commands below, and the staged artifact is just a file tree. Declaring
  # them under `depends:` staged them into /layer alongside this element, where
  # their headers collided with homebrew-runtime.bst (which keeps devel), failing
  # assembly with "is not permitted to overlap other elements". The shell brew
  # needs at runtime comes from homebrew-runtime.bst, not from here.
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
