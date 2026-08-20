kind: manual
description: |
  Compile the vendored xterm-ghostty terminfo entry into every image's
  terminfo database (#105).

  Ghostty sets TERM=xterm-ghostty by default, but ncurses' terminfo.src
  carries the entry only under the name "ghostty" (FSDK 26.08 ships
  ncurses 6.6, which includes it), so xterm-ghostty resolves nowhere
  upstream. Without it, `podman exec -it <container> tmux attach` dies
  with "missing or unsuitable terminal: xterm-ghostty" for Ghostty
  users.

  The entry source is Ghostty's own definition, vendored at
  elements/base/files/xterm-ghostty.terminfo with the "ghostty" alias
  dropped so it never shadows the ncurses database's own g/ghostty.
  It is compiled here with the FSDK-pinned ncurses' own tic, so the
  compiled entry always matches the libtinfo the image ships.

sources:
  - kind: local
    path: elements/base/files/xterm-ghostty.terminfo

build-depends:
  # The manual element's command interpreter and mkdir: runtime-gnu carries
  # bash, coreutils, glibc, and the gcc runtime libs (libgcc_s — coreutils
  # links it; staging bootstrap/coreutils.bst alone fails with
  # "libgcc_s.so.1: cannot open shared object file"). Same pattern as
  # lab-runner/just.bst.
  - freedesktop-sdk.bst:public-stacks/runtime-gnu.bst
  # tic, from the same ncurses that ships the runtime terminfo database.
  - freedesktop-sdk.bst:bootstrap/ncurses.bst

variables:
  # Data-only artifact: nothing to strip, and the default strip commands
  # need debug-utils tooling that is not staged here (exit 127). Same as
  # the other manual elements (lab-runner/just.bst et al).
  strip-binaries: ""

config:
  install-commands:
    # tic does not create the database root itself; mkdir first.
    - |
      mkdir -p "%{install-root}/usr/share/terminfo"
      tic -x -o "%{install-root}/usr/share/terminfo" xterm-ghostty.terminfo
