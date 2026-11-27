#!/bin/bash
set -euo pipefail

days=${1:-14}
main="$(git worktree list --porcelain 2>/dev/null | sed -n '1s/^worktree //p')"
if [ -z "$main" ]; then
    echo "repeats: not inside a git repository" >&2
    exit 2
fi
logs="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/projects/$(printf '%s' "$main" | sed 's|[/.]|-|g')"
if [ ! -d "$logs" ]; then
    echo "repeats: no session logs at $logs" >&2
    exit 3
fi
files="$(find "$logs" -name '*.jsonl' -mtime "-$days" 2>/dev/null)"
if [ -z "$files" ]; then
    echo "repeats: no session log changed in the last $days days under $logs" >&2
    exit 3
fi
count="$(printf '%s\n' "$files" | wc -l | tr -d ' ')"
echo "logs: $count session logs of the last $days days, $logs"

calls="$(mktemp)"
said="$(mktemp)"
trap 'rm -f "$calls" "$said"' EXIT
printf '%s\n' "$files" | while IFS= read -r file; do
    jq -r 'select(.type == "assistant") | .message.content[]? | select(.type == "tool_use") | [.name, ((.input.command // .input.file_path // .input.pattern // .input.skill // .input.description // "") | tostring | gsub("[\n\t]"; " "))] | @tsv' "$file" 2>/dev/null >> "$calls" || true
    jq -r 'select(.type == "user") | .message.content | if type == "string" then . else (map(select(.type == "text") | .text) | join(" ")) end | gsub("[\n\t]"; " ") | select(length > 0 and (startswith("<") | not))' "$file" 2>/dev/null >> "$said" || true
done

echo "tools: calls per tool"
cut -f1 "$calls" | sort | uniq -c | sort -rn | head -12 | sed 's/^/  /'

echo "commands: shell command shapes run 3 times or more, strings as S, numbers as N, absolute paths as P"
awk -F'\t' '$1 == "Bash" {print $2}' "$calls" \
    | sed -E 's/"[^"]*"/S/g; s/'"'"'[^'"'"']*'"'"'/S/g; s#(^| )/[^ ]+#\1P#g; s/[0-9]+/N/g' \
    | cut -c1-90 | sort | uniq -c | sort -rn | awk '$1 >= 3' | head -40 | sed 's/^/  /'

echo "reads: files read 4 times or more"
awk -F'\t' '$1 == "Read" {print $2}' "$calls" | sort | uniq -c | sort -rn | awk '$1 >= 4' | head -25 | sed 's/^/  /'

echo "edits: files edited 4 times or more"
awk -F'\t' '$1 == "Edit" || $1 == "Write" {print $2}' "$calls" | sort | uniq -c | sort -rn | awk '$1 >= 4' | head -20 | sed 's/^/  /'

echo "searches: patterns searched 3 times or more"
awk -F'\t' '$1 == "Grep" || $1 == "Glob" {print $2}' "$calls" | cut -c1-80 | sort | uniq -c | sort -rn | awk '$1 >= 3' | head -20 | sed 's/^/  /'

echo "skills: skills invoked"
awk -F'\t' '$1 == "Skill" {print $2}' "$calls" | sort | uniq -c | sort -rn | head -20 | sed 's/^/  /'

echo "corrections: what the user said that starts as a correction"
grep -iE '^(no[, .]|nope|stop|wrong|why did|i said|i told|do not|don.t|never|not what)' "$said" | cut -c1-200 | head -30 | sed 's/^/  /' || true

echo "answers: what the user answered to a numbered question"
grep -iE '^q[0-9]+' "$said" | cut -c1-200 | head -40 | sed 's/^/  /' || true
