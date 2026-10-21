#!/bin/bash
set -euo pipefail
repo=$1
ruby=$2
dest=$3
if [[ ! -d "$repo/.git" ]]; then
    echo 'Homebrew source must retain its real upstream Git repository' >&2
    exit 1
fi
version=$(cat "$repo/Library/Homebrew/vendor/portable-ruby-version")
[[ -x "$ruby/portable-ruby/$version/bin/ruby" ]]
seed="$dest/usr/share/bluefin/homebrew-seed"
mkdir -p "$seed/Homebrew" "$seed/bin" "$seed/etc" "$seed/share" \
    "$seed/Cellar" "$seed/opt" "$seed/lib" "$seed/var/homebrew" \
    "$dest/home/linuxbrew/.linuxbrew"
cp -a "$repo/." "$seed/Homebrew/"
# git_repo retains upstream commit/tree identity but omits regular-file blobs.
# Re-hash tracked worktree files into that object store, without a new commit,
# before checkout/fetch/reset can need them. Rebuilding the index below removes
# build-specific stat data; the pinned upstream commit and tag stay unchanged.
git -C "$seed/Homebrew" add --renormalize .
git -C "$seed/Homebrew" config core.logAllRefUpdates false
rm -rf "$seed/Homebrew/.git/logs"
git -C "$seed/Homebrew" checkout -B main
git -C "$seed/Homebrew" config remote.origin.url https://github.com/Homebrew/brew.git
git -C "$seed/Homebrew" config remote.origin.fetch '+refs/heads/*:refs/remotes/origin/*'
git -C "$seed/Homebrew" update-ref refs/remotes/origin/main HEAD
git -C "$seed/Homebrew" symbolic-ref refs/remotes/origin/HEAD refs/remotes/origin/main
git -C "$seed/Homebrew" config branch.main.remote origin
git -C "$seed/Homebrew" config branch.main.merge refs/heads/main
# A fresh tree-only index has no checkout ctime/inode fields from this build.
rm -f "$seed/Homebrew/.git/index"
git -C "$seed/Homebrew" read-tree HEAD
git -C "$seed/Homebrew" config core.logAllRefUpdates true
cp -a "$ruby/portable-ruby" "$seed/Homebrew/Library/Homebrew/vendor/"
ln -sfn "$version" "$seed/Homebrew/Library/Homebrew/vendor/portable-ruby/current"
ln -sf ../Homebrew/bin/brew "$seed/bin/brew"
