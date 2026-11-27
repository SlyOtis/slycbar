#!/bin/bash
set -euo pipefail
. "$(dirname "$0")/lib.sh"
cd "$main"

echo "tasks"
found=0
if [ -d "$board" ]; then
    for file in $(ls "$board" | grep -E '^[0-9]+-.*\.md$' | sort -n); do
        f="$board/$file"
        state="$(get "$f" status)"
        work="$(get "$f" tree)"
        [ "$state" = "done" ] && [ -z "$work" ] && continue
        found=1
        number="$(issue "$f")"
        pr="$(pull "$f")"
        echo "  $(get "$f" id)	$state	$(get "$f" title)	$work	${number:+issue $number}${number:-not synced}	${pr:+PR $pr}${pr:-no PR}"
    done
fi
[ "$found" = 1 ] || echo "  none"

echo "trees"
git worktree list --porcelain | awk '/^worktree /{tree=$2} /^branch /{sub("refs/heads/","",$2); print tree "\t" $2}' | while IFS=$'\t' read -r tree branch; do
    [ "$tree" = "$main" ] && continue
    dirty="clean"
    [ -n "$(git -C "$tree" status --porcelain 2>/dev/null)" ] && dirty="uncommitted"
    ahead="$(git rev-list --count "$(dev)..$branch" 2>/dev/null || echo 0)"
    echo "  $(basename "$tree")	$branch	$ahead not on $(dev)	$dirty"
done
unneeded

echo "served"
head="$(git rev-parse --abbrev-ref HEAD)"
if [ "$head" = "$(dev)" ]; then
    echo "  on $head, $(git rev-list --count origin/main..HEAD) commits over origin/main"
    git log --merges --format='  %s' origin/main..HEAD
else
    echo "  on $head, not on $(dev)"
fi
if [ -n "$(stack)" ]; then
    echo "  $(serving) is running in $name"
else
    echo "  $(serving) is not running in $name"
fi

echo "main"
git fetch -q origin main 2> /dev/null || true
echo "  $(git log --oneline -1 origin/main)"
