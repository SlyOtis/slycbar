#!/bin/bash
set -euo pipefail
. "$(dirname "$0")/lib.sh"
cd "$main"

case "${1:-}" in
    -h|--help|help)
        echo "usage: serve.sh [id ...]"
        echo "the primary checkout on $(dev) with the newest origin/main and the branches of those tasks merged, the tasks turned done through pass.sh;"
        echo "with no id, every task in review, testing or done that still has a tree line. It checks $(dev) out and merges."
        exit 2 ;;
esac

branch="$(dev)"
ids="$*"
if [ -z "$ids" ] && [ -d "$board" ]; then
    for entry in $(ls "$board" | grep -E '^[0-9]+-.*\.md$' | sort -n); do
        [ -n "$(get "$board/$entry" tree)" ] || continue
        case "$(get "$board/$entry" status)" in
            review|testing|done) ids="$ids $(get "$board/$entry" id)" ;;
        esac
    done
fi

for id in $ids; do
    file="$(task "$id")"
    work="$(get "$file" tree)"
    if [ -z "$work" ]; then
        echo "task $id: no branch in its tree line, nothing served"
        exit 3
    fi
    tree="$(checkout "$work")"
    if [ -n "$tree" ] && [ -n "$(git -C "$tree" status --porcelain 2>/dev/null)" ]; then
        echo "task $id: $tree has uncommitted changes, nothing served"
        exit 3
    fi
done

git fetch -q origin main
if git show-ref --verify --quiet "refs/heads/$branch"; then
    git checkout -q "$branch"
else
    git checkout -q -b "$branch" origin/main
    echo "branch: $branch cut from origin/main"
fi
before="$(git rev-parse HEAD)"
if ! git merge -q --no-edit origin/main; then
    git merge --abort
    echo "branch: origin/main does not merge into $branch, still at $(git rev-parse --short HEAD)"
    exit 4
fi
echo "base: $branch with $(git log --oneline -1 origin/main)"

for id in $ids; do
    file="$(task "$id")"
    work="$(get "$file" tree)"
    if ! git merge -q --no-edit "$work"; then
        git merge --abort
        echo "task $id: $work does not merge into $branch, which stays at $(git rev-parse --short HEAD)"
        exit 5
    fi
    put "$file" status "testing"
    echo "task $id: $work merged into $branch, testing"
done
bash "$(dirname "$0")/pass.sh"
unneeded

while IFS=$'\t' read -r paths say run; do
    [ -n "$paths" ] || continue
    if [ -n "$(git diff --name-only "$before" HEAD -- $paths)" ]; then
        echo "$say"
        echo "  $run"
    fi
done < <(fact '.after[]? | [(.paths | join(" ")), .say, .run] | @tsv')
if [ -n "$(stack)" ]; then
    echo "stack: left running in $name"
else
    echo "start: $(serving)"
fi
