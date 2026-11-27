#!/bin/bash
set -euo pipefail
. "$(dirname "$0")/lib.sh"
cd "$main"

mode=${1:-stop}
case "$mode" in
    stop|keep) ;;
    *) echo "usage: close.sh [stop|keep]"; exit 2 ;;
esac

echo "trees"
git worktree list --porcelain | awk '/^worktree /{print substr($0,10)}' | while read -r tree; do
    [ "$tree" = "$main" ] && continue
    if [ -n "$(git -C "$tree" status --porcelain 2>/dev/null)" ]; then
        echo "  $(basename "$tree"): uncommitted changes, kept"
        continue
    fi
    work="$(git -C "$tree" rev-parse --abbrev-ref HEAD)"
    state=""
    held=""
    for entry in $(ls "$board" 2>/dev/null | grep -E '^[0-9]+-.*\.md$'); do
        [ "$(get "$board/$entry" tree)" = "$work" ] || continue
        state="$(get "$board/$entry" status)"
        if [ "$state" != "done" ]; then
            held="$(get "$board/$entry" id) is $state"
        fi
    done
    if [ -z "$state" ] || [ -n "$held" ]; then
        echo "  $(basename "$tree"): task ${held:-unknown}, kept"
        continue
    fi
    git worktree remove "$tree"
    echo "  $(basename "$tree"): removed, $work stays"
done

echo "stack"
if [ "$mode" = "keep" ]; then
    echo "  left as it is"
    exit 0
fi
stopped=0
for pid in $(stack); do
    kill -INT -"$(ps -o pgid= -p "$pid" | tr -d ' ')" || true
    stopped=1
done
if [ "$stopped" = 1 ]; then
    echo "  $(serving) stopped in $name"
else
    echo "  $(serving) was not running in $name"
fi

echo "stop"
while IFS= read -r command; do
    [ -n "$command" ] || continue
    bash -c "$command" > /dev/null 2>&1 || true
    echo "  $command"
done < <(fact '.stop[]?')
