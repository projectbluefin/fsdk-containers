# Verify Distroless — The terminfo Seam (#101, #105)

Detail referenced from [`../SKILL.md`](../SKILL.md). Read the skill first.

Every image composed from `base-stack` keeps the ncurses terminfo database
(~0.5 MB compressed): without it a container must lie about the host TERM or
vendor its own entries, both of which produced real color/rendering bugs
downstream (projectbluefin/review). (`static` is the exception — it ships
certs + tzdata only, no ncurses.)

One entry is NOT upstream's: ncurses' terminfo.src carries Ghostty's
description only under the name `ghostty`, but Ghostty sets
`TERM=xterm-ghostty` by default, so `podman exec -it <container> tmux attach`
died with `missing or unsuitable terminal: xterm-ghostty` for Ghostty users
(#105). `elements/base/terminfo-ghostty.bst` compiles Ghostty's own entry
(vendored at `elements/base/files/xterm-ghostty.terminfo`, with the `ghostty`
alias dropped so it never shadows ncurses' own `g/ghostty`) using the
FSDK-pinned ncurses' `tic`, and `base/base-stack.bst` depends on it so it
lands in every base-derived image. The lab-runner terminfo gate asserts
`usr/share/terminfo/x/xterm-ghostty` exists.

To refresh the vendored entry after a Ghostty change: on a host running the
new Ghostty, regenerate with `infocmp -x xterm-ghostty`, drop the `ghostty`
alias from the names line again, and keep the provenance header current.
