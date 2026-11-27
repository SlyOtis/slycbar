#!/bin/bash

main="$(git worktree list --porcelain | sed -n '1s/^worktree //p')"
board="$main/.claude/tasks"
name="$(basename "$main")"
facts="$main/.claude/slyed.json"

fact() {
    [ -f "$facts" ] || return 0
    jq -r "$1 // empty" "$facts"
}

get() {
    awk -v k="$2" 'BEGIN{n=0} /^---$/{n++; next} n==1 && $0 ~ "^"k":" {sub("^"k": ?",""); print; exit}' "$1"
}

put() {
    local file="$1" key="$2" value="$3" now
    now="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    awk -v k="$key" -v v="$value" -v now="$now" 'BEGIN{n=0}
        /^---$/{n++; print; next}
        n==1 && $0 ~ "^"k":" {print (v=="" ? k":" : k": "v); next}
        n==1 && /^updated_at:/ {print "updated_at: "now; next}
        {print}' "$file" > "$file.tmp"
    mv "$file.tmp" "$file"
}

task() {
    local file
    file="$(ls "$board" 2>/dev/null | grep -E "^$1-.*\.md$" | head -1)"
    if [ -z "$file" ]; then
        echo "task $1: no file under .claude/tasks" >&2
        exit 2
    fi
    echo "$board/$file"
}

slug() {
    basename "$1" .md | sed 's/^[0-9]*-//'
}

issue() {
    local url
    url="$(get "$1" github)"
    echo "${url##*/}"
}

pull() {
    get "$1" tags | tr -d '[] ' | tr ',' '\n' | sed -n 's/^pr-//p' | head -1
}

checkout() {
    git -C "$main" worktree list --porcelain | awk -v b="refs/heads/$1" '/^worktree /{t=substr($0,10)} $1=="branch" && $2==b {print t}'
}

stack() {
    local pid
    for pid in $(pgrep -fx "$(serving)" || true); do
        [ "$(lsof -a -p "$pid" -d cwd -Fn 2>/dev/null | sed -n 's/^n//p')" = "$main" ] && echo "$pid"
    done
    return 0
}

unneeded() {
    local tree work entry keep lines=""
    while IFS=$'\t' read -r tree work; do
        [ "$tree" = "$main" ] && continue
        [ -n "$(git -C "$tree" status --porcelain 2>/dev/null)" ] && continue
        [ "$(git -C "$main" rev-list --count "$(dev)..$work" 2>/dev/null || echo 1)" = 0 ] || continue
        keep=0
        for entry in $(ls "$board" 2>/dev/null | grep -E '^[0-9]+-.*\.md$'); do
            [ "$(get "$board/$entry" tree)" = "$work" ] || continue
            [ "$(get "$board/$entry" status)" = "done" ] || keep=1
        done
        if [ "$keep" = 0 ]; then
            lines="$lines  git -C \"$main\" worktree remove \"$tree\""$'\n'
        fi
    done < <(git -C "$main" worktree list --porcelain | awk '/^worktree /{tree=substr($0,10)} /^branch /{sub("refs/heads/","",$2); print tree "\t" $2}')
    if [ -n "$lines" ]; then
        echo "no longer needed: clean, wholly on $(dev) and every task of it testing or done; the branch stays and tree.sh brings the tree back"
        printf '%s' "$lines"
    fi
    return 0
}

serving() {
    local command
    command="$(fact .dev)"
    echo "${command:-just dev}"
}

dev() {
    local branch
    branch="$(fact .branch)"
    echo "${branch:-main}"
}

rebranch() {
    local file="$1" number="$2" old new
    old="$(get "$file" tree)"
    new="${old%%/*}/$number-$(slug "$file")"
    [ "$old" = "$new" ] && return 0
    if git -C "$main" ls-remote --exit-code --heads origin "$old" > /dev/null 2>&1; then
        echo "task $(get "$file" id): $old is on origin and keeps its name"
        return 0
    fi
    if git -C "$main" show-ref --verify --quiet "refs/heads/$old"; then
        git -C "$main" branch -m "$old" "$new"
    fi
    put "$file" tree "$new"
    echo "task $(get "$file" id): branch $new"
}
