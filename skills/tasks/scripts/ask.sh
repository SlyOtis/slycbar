#!/bin/bash
set -euo pipefail
. "$(dirname "$0")/lib.sh"

id=${1:?task id}
label=${2:?question label, Q<n>}
shift 2
words=${*:?the question}
file="$(task "$id")"
line="  - \"$label: ${words//\"/\'}\""
if grep -q "^  - \"$label: " "$file"; then
    echo "task $id: $label is already open"
    exit 3
fi
awk -v line="$line" 'BEGIN{n=0}
    /^---$/{n++}
    n==1 && /^questions: \[\]$/ {print "questions:"; print line; next}
    n==1 && /^questions:$/ {print; print line; next}
    {print}' "$file" > "$file.tmp"
mv "$file.tmp" "$file"
put "$file" status blocked
put "$file" blocked_from "$label"
echo "task $id: $label open, blocked"
