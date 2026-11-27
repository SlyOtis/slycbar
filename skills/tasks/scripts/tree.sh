#!/bin/bash
set -euo pipefail
. "$(dirname "$0")/lib.sh"

id=${1:?task id}
shift
file="$(task "$id")"
branch="$(get "$file" tree)"
if [ -z "$branch" ]; then
    echo "task $id: no branch in its tree line"
    exit 2
fi
tree="$(checkout "$branch")"
existed=1
if [ -z "$tree" ]; then
    existed=0
    tree="$(dirname "$main")/$name-$(echo "${branch#*/}" | sed 's/^[0-9]*-//')"
fi

if [ "$existed" = 1 ] && [ $# -eq 0 ]; then
    echo "tree: $tree exists"
    exit 2
fi

cd "$main"
if [ "$existed" = 1 ]; then
    echo "tree: $tree exists on $branch"
else
    git fetch -q origin main
    from="$(dev)"
    if ! git show-ref --verify --quiet "refs/heads/$from"; then
        git branch -q "$from" origin/main
        echo "branch: $from cut from origin/main"
    fi
    if git show-ref --verify --quiet "refs/heads/$branch"; then
        git worktree add -q "$tree" "$branch"
    elif git ls-remote --exit-code --heads origin "$branch" > /dev/null 2>&1; then
        git worktree add -q --track -b "$branch" "$tree" "origin/$branch"
    else
        git worktree add -q -b "$branch" "$tree" "$from"
    fi
    echo "tree: $tree on $branch from $from"

    while IFS= read -r link; do
        [ -n "$link" ] || continue
        if [ -e "$main/$link" ]; then
            mkdir -p "$(dirname "$tree/$link")"
            ln -s "$main/$link" "$tree/$link"
            echo "$link: the primary checkout's"
        else
            echo "$link: none on the primary checkout"
        fi
    done < <(fact '.links[]?')
    echo "nothing of its own beyond the checkout and those links"

    [ -n "$(get "$file" base)" ] || put "$file" base "$(git -C "$tree" merge-base HEAD "$from")"
    put "$file" status doing
    echo "task $id: doing"
fi

for other in "$@"; do
    joined="$(task "$other")"
    put "$joined" tree "$branch"
    put "$joined" base "$(git -C "$tree" rev-parse HEAD)"
    put "$joined" status doing
    echo "task $other: doing in $(basename "$tree") on $branch"
done
echo "$tree"
