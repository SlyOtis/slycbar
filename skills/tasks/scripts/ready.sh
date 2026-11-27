#!/bin/bash
set -euo pipefail
. "$(dirname "$0")/lib.sh"
cd "$main"

branch="$(dev)"
git fetch -q origin main
if ! git show-ref --verify --quiet "refs/heads/$branch"; then
    echo "branch: $branch does not exist, nothing is merged into it"
    exit 2
fi

missing=0
closes=""
count=0
for entry in $(ls "$board" 2>/dev/null | grep -E '^[0-9]+-.*\.md$' | sort -n); do
    file="$board/$entry"
    if [ "$(get "$file" status)" = "testing" ]; then
        echo "task $(get "$file" id): in testing, the complete suites have not passed for it"
        missing=1
        count=$((count + 1))
        continue
    fi
    [ "$(get "$file" status)" = "done" ] || continue
    work="$(get "$file" tree)"
    [ -n "$work" ] || continue
    [ -z "$(pull "$file")" ] || continue
    id="$(get "$file" id)"
    number="$(issue "$file")"
    count=$((count + 1))
    if ! git merge-base --is-ancestor "$work" "$branch"; then
        echo "task $id: $work is not merged into $branch at its newest commit"
        missing=1
    fi
    if ! grep -q '^## Result$' "$file"; then
        echo "task $id: no ## Result in the task file"
        missing=1
    fi
    if ! grep -q '^served: ' "$file"; then
        echo "task $id: no served: line from the tester under ## Result"
        missing=1
    fi
    if [ -z "$number" ]; then
        echo "task $id: no issue, the sync has not run for it"
        missing=1
    fi
    [ -n "$number" ] && closes="$closes
Closes #$number"
    echo "task $id: $(get "$file" title)"
done

if [ "$count" = 0 ]; then
    echo "no task is done and waiting for a pull request"
    exit 2
fi
if [ "$missing" = 1 ]; then
    echo "not ready"
    exit 3
fi
echo "ready: $branch, $(git rev-list --count origin/main.."$branch") commits over origin/main"
printf '%s\n' "$closes" | sed '/^$/d'
