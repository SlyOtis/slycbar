#!/bin/bash
set -euo pipefail
. "$(dirname "$0")/lib.sh"

id=${1:?task id}
label=${2:?question label, Q<n>}
shift 2
words=${*:?the answer}
file="$(task "$id")"
asked="$(sed -n "s/^  - \"$label: \(.*\)\"$/\1/p" "$file" | head -1)"
if [ -z "$asked" ]; then
    echo "task $id: $label is not open"
    exit 3
fi
grep -v "^  - \"$label: " "$file" > "$file.tmp"
mv "$file.tmp" "$file"
if ! grep -q '^  - "' "$file"; then
    awk 'BEGIN{n=0} /^---$/{n++} n==1 && /^questions:$/ {print "questions: []"; next} {print}' "$file" > "$file.tmp"
    mv "$file.tmp" "$file"
    put "$file" blocked_from ""
    put "$file" status draft
fi
grep -q '^## Answers$' "$file" || printf '\n## Answers\n\n' >> "$file"
printf -- '- %s: %s\n  %s\n' "$label" "$asked" "$words" >> "$file"
put "$file" id "$(get "$file" id)"
echo "task $id: $label answered"
