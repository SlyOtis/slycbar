#!/bin/bash
set -euo pipefail
. "$(dirname "$0")/lib.sh"

id=${1:?task id}
file="$(task "$id")"
branch="$(get "$file" tree)"
tree=""
[ -n "$branch" ] && tree="$(checkout "$branch")"

cd "$main"
git fetch -q origin main
if [ -n "$tree" ] && [ -n "$(git -C "$tree" status --porcelain)" ]; then
    echo "tree: $tree has uncommitted changes"
    exit 3
fi
if [ -n "$branch" ] && git show-ref --verify --quiet "refs/heads/$branch" && [ "$(git rev-list --count "origin/main..$branch")" != 0 ]; then
    echo "task $id: $branch has commits that are not on origin/main, push main first"
    exit 4
fi

if [ -n "$tree" ]; then
    git worktree remove "$tree"
    echo "tree: $tree removed"
fi
if [ -n "$branch" ]; then
    git show-ref --verify --quiet "refs/heads/$branch" && git branch -q -D "$branch"
    git push -q origin --delete "$branch" 2> /dev/null || true
fi
put "$file" tree ""
put "$file" session ""
put "$file" status "done"
echo "task $id: done and landed, ${branch:-no branch} removed"
echo "main: $(git log --oneline -1 origin/main)"
