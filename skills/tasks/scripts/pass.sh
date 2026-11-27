#!/bin/bash
set -euo pipefail
. "$(dirname "$0")/lib.sh"
cd "$main"

case "${1:-}" in
    -h|--help|help)
        echo "usage: pass.sh"
        echo "serve.sh runs it once the scope has passed: every task in testing turns done."
        exit 2 ;;
esac

count=0
for entry in $(ls "$board" 2>/dev/null | grep -E '^[0-9]+-.*\.md$' | sort -n); do
    file="$board/$entry"
    [ "$(get "$file" status)" = "testing" ] || continue
    put "$file" status "done"
    echo "task $(get "$file" id): done"
    count=$((count + 1))
done
[ "$count" -gt 0 ] || echo "no task is in testing"
