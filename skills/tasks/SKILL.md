---
name: tasks
description: Moves work through a repo as local task files under .claude/tasks, one file per task with lcp frontmatter, built in git worktrees cut from the working branch and merged back as soon as they build. Use when the user hands over a task, a fix or a list of them, when a task is to be built or served, when an agent reports, when a question to the user must be recorded on a task or its answer written back, when a merged branch is to be cleaned up, or when the user asks what is in motion.
argument-hint: "[board|take <title> <slug>|tree <id> [id ...]|serve [id ...]|ask <id> <Q> <words>|answer <id> <Q> <words>|land <id>]"
allowed-tools: Bash(bash */skills/tasks/scripts/*), Bash(git *), Agent, SendMessage, Read, Grep, Glob
---

# tasks

The board is local: one file per task under `.claude/tasks/` of the primary checkout. The scripts own every state change, so the board is read with `board.sh` and never restated from memory. What differs between repos is not in this skill: the working branch, the gate, the dev command, the files a worktree links and what to run after a merge are the facts in `.claude/slyed.json`, written by the `slyed-init` skill, and the agents that build are the repo's own under `.claude/agents/`.

## The scripts

Run from inside the repo as `bash <this skill's base directory>/scripts/<name>.sh`.

```
board.sh                           every open task, every worktree, the removal command of each worktree no longer needed, what the primary checkout serves
take.sh "<title>" <slug> [feat|fix] [words]   the task file <id>-<slug>.md, numbered after the last
tree.sh <id> [id ...]              the worktree ../<repo>-<slug> of the first id on its branch, cut from the working branch; every id named turns doing there
serve.sh [id ...]                  the primary checkout on the working branch with the newest origin/main and those branches merged; the tasks turn done through pass.sh
pass.sh                            every task in testing turns done
ask.sh <id> <Q<n>> <words>         the question added to the task's questions, the task blocked on it
answer.sh <id> <Q<n>> <words>      the question taken off the task, question and answer written under ## Answers, the task unblocked when none is left
ready.sh                           whether the work on the working branch may be pushed: every done task merged, with a ## Result, a served: line and an issue
land.sh <id>                       once its branch is on origin/main: the worktree and the branch removed, the tree line emptied
close.sh [stop|keep]               every clean worktree whose tasks are done removed, the dev command stopped, the repo's stop commands run
```

## The task file

Frontmatter in lcp's order: `id`, `parent`, `depends`, `relations`, `title`, `type`, `size`, `status`, `tree`, `session`, `review`, `blocked_from`, `retries`, `github`, `assignee`, `description`, `tags`, `scope`, `repos`, `skills`, `base`, `commits`, `created_at`, `updated_at`, `questions`, `images`, then the user's words. `status` is `draft` when taken, `doing` in a tree, `review` when committed and not merged, `testing` while merged and unproven, `done` once proven, `blocked` with `blocked_from` while a question is open. `tree` is the branch; the worktree is found from it. `session` is the name of the agent that holds the task. Below the words the builder adds `## Trace`, `## Scope`, `## Stopped` and `## Result`; `## Answers` holds every answered question and `## Review` every rejection that came back from a review in Slyed.

## The flow

1. Every piece of work becomes a task before anything else: `take.sh` with the user's words as they were said. A list is one task per item in the order given.
2. Before it is built, read the code it names to the end of the call chain and say how it works today. What only the user can decide is asked as a numbered question and recorded with `ask.sh`; a task is built only when it has no open question.
3. An answer the user gives is written back with `answer.sh` before the work continues, so the ruling stays with the task and is never asked twice.
4. `tree.sh` cuts the worktree. Tasks on the same files share one tree; a task that shares nothing with an open tree gets its own.
5. A tree is served as soon as every task in it is committed and its gate, the `gate` of `.claude/slyed.json`, has passed there: `serve.sh` with every id of that tree. A branch that does not merge leaves the working branch where it was.
6. `serve.sh` and `board.sh` print the removal command of each worktree no longer needed. That line is handed to the user as it is and never run.
7. A rejection written under `## Review` is the next thing built for that task: only the rejected spots, each answered in the same section.
8. `ready.sh` before a push, `land.sh <id>` once the branch is on `origin/main`.

## Hand over

A task is named `#<id>` as a markdown link to its file. Per task: its state, its tree and what waits on the user, then every removal command that is due.
