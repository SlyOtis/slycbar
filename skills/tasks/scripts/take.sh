#!/bin/bash
set -euo pipefail
. "$(dirname "$0")/lib.sh"

title=${1:?title}
slug=${2:?slug}
kind=${3:-feat}
shift 2
[ $# -gt 0 ] && shift
words=${*:-}

case "$kind" in
    feat) type=feature ;;
    fix) type=fix ;;
    *) echo "kind: $kind is neither feat nor fix"; exit 2 ;;
esac

mkdir -p "$board"
if ls "$board" | grep -qE "^[0-9]+-$slug\.md$"; then
    echo "task: $(ls "$board" | grep -E "^[0-9]+-$slug\.md$") already holds $slug"
    exit 3
fi

last=$(ls "$board" | sed -n 's/^\([0-9][0-9]*\)-.*\.md$/\1/p' | sort -n | tail -1)
id=$(( 10#${last:-0} + 1 ))
file="$board/$id-$slug.md"
now="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

{
    echo "---"
    echo "id: $id"
    echo "parent:"
    echo "depends: []"
    echo "relations: []"
    echo "title: $title"
    echo "type: $type"
    echo "size:"
    echo "status: draft"
    echo "tree: $kind/$id-$slug"
    echo "session:"
    echo "review:"
    echo "blocked_from:"
    echo "retries:"
    echo "github:"
    echo "assignee: $(git -C "$main" config user.name)"
    echo "description:"
    echo "tags: []"
    echo "scope: []"
    echo "repos: []"
    echo "skills: []"
    echo "base:"
    echo "commits: []"
    echo "created_at: $now"
    echo "updated_at: $now"
    echo "questions: []"
    echo "images: []"
    echo "---"
    echo
    echo "$words"
} > "$file"
echo "task $id: $title"
echo "$file"
