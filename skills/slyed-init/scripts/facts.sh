#!/bin/bash
set -euo pipefail

main="$(git worktree list --porcelain 2>/dev/null | sed -n '1s/^worktree //p')"
if [ -z "$main" ]; then
    echo "facts: not inside a git repository" >&2
    exit 2
fi
file="$main/.claude/slyed.json"
mode=${1:-show}
cd "$main"

recipes=""
[ -f justfile ] && recipes="$(grep -E '^[a-z][a-z0-9_-]*[^=]*:($|[^=])' justfile | sed -E 's/^([a-z][a-z0-9_-]*).*/\1/' | sort -u)"
has() { printf '%s\n' "$recipes" | grep -qx "$1"; }
gate=""
for name in check test build; do
    if has "$name"; then gate="just $name"; break; fi
done
dev=""
has dev && dev="just dev"
branch="$(git symbolic-ref -q --short refs/remotes/origin/HEAD 2>/dev/null | sed "s|^origin/||" || true)"
links="$( { [ -f .env ] && echo .env; find . -maxdepth 3 -name node_modules -type d -prune -not -path './.git/*' 2>/dev/null | sed 's|^\./||'; } | jq -R . | jq -sc .)"
found="$(jq -n --arg branch "${branch:-main}" --arg gate "$gate" --arg dev "$dev" --argjson links "$links" '{branch: $branch, gate: $gate, dev: $dev, links: $links, after: [], stop: []}')"

echo "recipes: $(printf '%s' "$recipes" | tr '\n' ' ')"
echo "surfaces:"
git ls-files | awk -F/ 'NF>1 {n=split($NF, part, "."); ext=(n>1 ? part[n] : "-"); count[$1 "\t" ext]++} END {for (key in count) if (count[key] >= 5) print "  " count[key] "\t" key}' | sort -rn | head -24
echo "agents: $(ls .claude/agents 2>/dev/null | tr '\n' ' ')"
echo "skills: $(ls .claude/skills 2>/dev/null | tr '\n' ' ')"
echo "tasks: $(ls .claude/tasks 2>/dev/null | grep -c '\.md$' || true)"
if [ -f "$file" ]; then
    echo "facts: $file exists"
    cat "$file"
    exit 0
fi
echo "facts: proposed for $file"
printf '%s\n' "$found"
if [ "$mode" = "write" ]; then
    mkdir -p "$main/.claude"
    printf '%s\n' "$found" > "$file"
    echo "facts: written"
fi
