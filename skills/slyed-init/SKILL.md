---
name: slyed-init
description: Sets a project up for the tasks system and for Slyed, writing the project's facts file, its agents and its own skills under the project's .claude folder from what the repo actually contains. Use when a repo is to be initialised for tasks, when .claude/slyed.json is missing or out of date, when a project needs its task and specialist agents created or aligned, or when the user says init, set up or onboard this project.
argument-hint: "[show|write]"
allowed-tools: Bash(bash */skills/slyed-init/scripts/*), Bash(git *), Bash(just --list), Read, Grep, Glob, Edit, Write, Skill
---

# slyed-init

The generic part of the tasks system ships with the plugin. This skill writes the part that is the project's own, inside the project's `.claude` folder, so the generic scripts and Slyed find it. It writes there on its own standing permission, and nothing outside `.claude`.

## What it writes

1. `.claude/slyed.json`, the facts the `tasks` scripts read:
   - `branch`: the working branch every worktree is cut from and merged back into.
   - `gate`: the one command that must pass before a tree is merged.
   - `dev`: the command that serves the primary checkout.
   - `links`: paths a worktree links from the primary checkout and never builds itself.
   - `after`: `{paths, say, run}` entries, a command to hand over when a merge touched those paths.
   - `stop`: commands `close.sh` runs when the work is closed.
2. `.claude/agents/task.md`, the orchestrator of one unit of work, and one specialist agent per surface the repo has.
3. A repo skill for each procedure the repo has that no plugin skill covers.

## Process

1. `bash <this skill's base directory>/scripts/facts.sh` prints the justfile recipes, the surfaces by folder and file type, the agents and skills already there, and the proposed facts. `facts.sh write` writes the facts file when none exists; an existing one is edited in place.
2. Read the repo's `CLAUDE.md` and its rules before writing an agent: an agent restates none of them, it points to them.
3. One specialist per surface with its own language, tooling or contract, named for the surface. A surface with fewer than a handful of files gets no agent of its own.
4. Each agent file is written as the `agent-markdown` skill says: a description that says what it owns and when it is launched, the contract it must not break, the mechanism it must reuse, the gate it runs, and what it returns. `model` and `effort` are set to the least that does the job; the orchestrator traces and delegates and writes no application code.
5. The `task` agent groups tasks into as few worktrees as the work allows, hands each surface to its specialist, holds each diff to its task's scope, and returns per task `merged` or `stopped`, with every worktree removal command as a `remove:` line.
6. Everything deterministic an agent would otherwise spell out is a script beside the skill that owns it.

## Verification

`facts.sh` reads the written file back, `bash <tasks base directory>/scripts/board.sh` runs clean, and every path an agent names exists.
