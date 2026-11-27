---
name: space-n-resources
description: Finds what takes disk space, memory and cpu on this Mac, then turns what can go into copyable commands. `slybar space` analyses, walking the home folder once and caching it, and reports free space, the usual suspects, docker, models, simulators, build artifacts, the heaviest processes, dev servers, orphaned browsers and mcp servers, and every claude session with the memory of its process tree; its candidates view lists what is orphaned, stale, cache, redundant or data, and `slybar space candidates | slybar space free` turns that list into a reason and a copyable kill, rm or prune command for each. Its running view lists what runs right now, idle and rogue claude sessions, listening servers, lost processes, what closed sessions left behind, duplicates, heavy processes, open applications, containers and OrbStack, and pause stops every other claude session so one session has the machine. The space_guard hook refuses a write that leaves the disk under 2G free and logs every session and the processes its tool calls start. Use when asked what is taking up space, what is slowing the machine down, what can be removed or closed, why the fans spin, or to clean up disk or memory, and when the machine freezes, crashes or runs out of memory.
allowed-tools: Bash(slybar space *)
---

Four commands of the slybar cli, one job each. `slybar space check` says in 20 ms whether disk, memory or cpu is over its limit; `slybar space` analyses; `slybar space free` turns what it found into commands; `slybar space log` is the hook's process log. The answer is read from their output, not from new `du` or `ps` calls.

```
slybar space check [path] [bytes]   disk free, memory used, cpu used, each with its limit and ok or over; exit 1 when any is over
slybar space all                    disk, then memory and cpu
slybar space disk                   free space, home, library, the usual suspects, docker, models, simulators, files over 500M
slybar space build [days]           build artifacts under ~/Projects, largest first, stale when the project is untouched for days (60)
slybar space mem                    swap, pressure, load, top cpu, processes over 150M, apps summed, dev servers, orphans, claude sessions
slybar space candidates [days]      one tab separated row per thing that can go: kind, kb, action, target, why, group
slybar space running                what runs now: idle and rogue claude sessions, listening servers, lost processes, what closed sessions left, duplicates, processes over 150M, headless browsers, open applications, containers, orbstack
slybar space pause                  kill -STOP every claude session and its process tree except the one asking
slybar space resume                 kill -CONT what pause stopped
slybar space free [--kind orphan,stale,cache,redundant,data,running,rogue]   reads candidates or running rows on stdin and prints the groups with their commands

slybar space candidates | slybar space free
slybar space running | slybar space free
```

## When the machine freezes or runs out of resources

`running` is the view for this: it reads `ps`, `lsof`, `launchctl` and the `space_guard` log only, walks no disk, never starts OrbStack and answers in seconds. It lists everything else that runs, what `candidates` protects included. The asking session is never listed as a session, and neither is a claude session whose transcript moved in the last 30 minutes: that is what the person is working in.

1. `slybar space pause` first. Every other claude session and everything in its tree is stopped with `kill -STOP`, nothing is lost, and the pids are kept in `$TMPDIR/space-n-resources.paused`. Run from a plain terminal it pauses every session.
2. `slybar space running | slybar space free`, handed over group by group: `processes`, `servers`, `containers`, `open applications`, `sessions`, `rogue sessions`.
3. The person confirms a group, or names what in it goes. Only then is that command run, as `slybar space free` printed it.
4. `slybar space resume` when the person says so. A paused claude session sits suspended in its terminal and comes back with `fg` there.

What `running` counts as what:

1. `orphan`: a process of the user whose parent is gone and that no launchd job owns; a process carrying the `CLAUDE_CODE_SESSION_ID` of a session that has ended; a process the log holds whose claude session has closed, named with the tool that started it and the session's folder.
2. `stale`: a process the log holds whose claude session still runs but has not moved its transcript in 6 hours.
3. `redundant`: every instance but the newest of the same command in the same folder under the same session, alive for more than 5 minutes; every server but the newest listening from the same command in the same folder; every container but the newest of the same image.
4. `rogue`: a claude session with no Ghostty in its parent chain, started from an editor, a desktop app, a multiplexer or launchd, named with what started it. It is listed whether or not it is active.
5. `running`: in use, and stops only on the person's word. A server listening on a tcp port from a folder under home, with its port, its folder and the session that started it; a headless browser; any other process of the user over 150M, with the session and the tool that started it; an application under `/Applications` or `~/Applications` whose processes sum over 150M, with `osascript -e 'quit app "<name>"'`, Ghostty never; a running container, with `docker stop`; OrbStack itself, with `orb stop`; another claude session idle for 30 minutes or more, with the memory and the count of its whole tree.

When docker is down it stays down: `running` says `docker is down, orbstack was not started` and lists no container.

## The hook and its log

`~/.claude/hooks/space_guard.sh` is registered in `~/.claude/settings.json` on `SessionStart`, on `PreToolUse` for `Edit|Write|MultiEdit|NotebookEdit` and for `Bash|mcp__.*|Agent|Task`, and on `PostToolUse` for `Bash|mcp__.*|Agent|Task`. It holds no logic of its own: it reads the event, calls `slybar space check` before a tool starts and `slybar space log` around the tools that start processes.

`slybar space check [path] [bytes]` is the one fast read of the machine, 20 ms, callable by hand. It prints a tab separated row each for `disk`, `mem` and `cpu`: name, value, limit, `ok` or `over`. `disk` is the megabytes free on the volume of the path after the bytes are written, over when under `SPACE_MIN_FREE_MB` (2048); `mem` is the percent of memory used, 100 minus `kern.memorystatus_level`, over when above `SPACE_MAX_MEM` (90); `cpu` is the percent of all cores used, over when above `SPACE_MAX_CPU` (90). It exits 0 when all are ok, 1 when any is over, 2 when a source cannot be read.

1. Before every write, Bash, mcp or agent call the hook runs `slybar space check`. A write that would leave `disk` over is denied. Any other `over` does not block: the session is told the numbers and to run `slybar space running | slybar space free` for what can be killed and `slybar space candidates | slybar space free` for what frees storage, and it hands the groups to the person. It is told once per `SPACE_TOLD_MIN` (10) minutes per session, not on every call.
2. `slybar space log`, on every event but a write, appends to `~/.claude/space-n-resources.log` (`SPACE_LOG`) one tab separated row per process of the session it has not logged yet: epoch, session id, claude pid, origin, tool, pid, start time, the session's folder, command. The session's tree and every process carrying its `CLAUDE_CODE_SESSION_ID` count; the hooks' own processes do not. The claude process is the row whose tool is `session` and whose pid is the claude pid. A process seen before a tool call or at session start has the tool `session`; one that appears after a tool call has that tool's name, `Bash` or the `mcp__<server>__<tool>` that started it.
3. `origin` is `ghostty` when Ghostty is in the session's parent chain, else the name of the topmost parent.
4. The pid and its start time together identify a process, so a reused pid is never mistaken. On `SessionStart`, and whenever the log passes `SPACE_LOG_ROWS` (2000) rows, the rows of processes that no longer run are dropped.

## Active work is never listed

What the person or a claude session is working on never becomes a candidate:

1. A folder is active when any process has its working directory there, a terminal, an editor, a dev server or a claude session, or when a claude session's transcript for it moved in the last 6 hours. Everything inside an active project is kept, and a project inside an active folder at least three levels below home is kept too; a shell in a group folder such as `~/Projects/acme` does not keep its sibling projects. A Rust build is the one exception: it is listed in an active project too.
2. A cache is active while a running process loads from it, such as the pnpm `dlx` folder the mcp servers run out of, or holds a file open in it, read from one `lsof` pass; a running application keeps its `~/Library/Caches` folder that way.
3. A build folder git tracks a file in is source, not output, and is never listed.
4. Docker containers of a compose project in an active folder are kept, and named volumes are never listed; only anonymous volumes no container uses are, by id, never pruned wholesale.
5. An emulator that is running is kept; an installer downloaded in the last day is kept.
6. A process in the tree of any running claude session, the session asking included, is never listed: its mcp servers, dev servers, browsers and shells stay. Only the session itself can be listed, as `stale`, when its transcript has not moved in 6 hours.

## What counts as what

1. `orphan`: a `pnpm dlx`, `npm exec`, `uvx`, mcp or `claude -p` process whose parent is gone.
2. `stale`: a claude session whose transcript has not moved in 6 hours; a vite, storybook, air or `go run` dev server older than a day with no claude work in its folder for 6 hours; stopped docker containers; a build folder over 50M in a project untouched for 60 days: node `node_modules`, `dist`, `build`, `.next`, `.nuxt`, `.output`, `.svelte-kit`, `.angular`, `.expo`, `.turbo`, `.parcel-cache`, `.vite`; Rust and Maven `target`; Swift `.build`; Gradle `.gradle` and `build`; Python `__pycache__`, `.venv`, `.mypy_cache`, `.pytest_cache`, `.ruff_cache`, `.tox`; Zig `zig-cache`, `.zig-cache`, `zig-out`; Elixir `_build`; Dart `.dart_tool`; CMake `cmake-build-*` and `.cxx`; Go `vendor`, and `bin` beside a `go.mod` when git ignores it; Xcode `DerivedData`; in a project that moved in those 60 days but has no process and no claude work in it, a Rust build of a `target` beside a `Cargo.toml` (`debug`, `release`, a custom profile, `doc`, a target triple or `tmp`) over 100M not written for 14 days, with `cargo clean --manifest-path <Cargo.toml> --profile <dev|name>`, `--doc`, or `rm -rf` for the rest, and the `incremental` folders of crates in a Rust build still in use that were not written for 14 days, over 100M together, with one `find … -mtime +14 -exec rm -rf {} +`; a git worktree of a repo under `~/Projects` that is clean, has no process in it, did not move for 6 hours, is named by no task under the repo's `.claude/tasks` that is still open, building or built, and whose branch is either wholly on the primary checkout's head or untouched for 14 days, removed with `git -C <repo> worktree remove <tree>` so the branch stays; a worktree record whose folder is gone, with `git worktree prune`.
3. `cache`: rebuilds itself. Each over 100M, with the tool's own clean command where it has one and `rm -rf` otherwise. Go build cache (`go clean -cache -testcache`) and module cache (`go clean -modcache`), pnpm store and cache, npm, uv, homebrew, the cargo registry (`cargo cache --autoclean` when cargo-cache is installed) and cargo git checkouts, gradle caches, maven `~/.m2/repository`, pip and poetry, CocoaPods (`pod cache clean --all`), bun (`bun pm cache rm`), deno (`deno clean`), yarn and yarn berry, dart (`dart pub cache clean --force`), hex, swiftpm, node-gyp, typescript, electron and electron-builder downloads, gopls, golangci-lint (`golangci-lint cache clean`), pre-commit, playwright, playwright mcp and playwright go browsers, Xcode derived data, trash, unused docker images and build cache. Under `build folders`, in a project that moved but has no process and no claude work in it, a pure cache folder over 50M not written for 14 days (`.turbo`, `.parcel-cache`, `.vite`, `.svelte-kit`, `.nuxt`, `.angular`, `.expo`, `.mypy_cache`, `.pytest_cache`, `.ruff_cache`, `.tox`, `zig-cache`, `.zig-cache`, `.dart_tool`) and `.next/cache`; every Rust build of a `target` beside a `Cargo.toml` over 100M that was written in the last 14 days, in use or not, with the same `cargo clean` command as under `stale`, rebuilt in full on the next build. Under `tool caches`, every other folder over 100M in `~/.cache`; under `app caches`, every other folder over 100M in `~/Library/Caches`; neither when a process holds a file in it, and never `com.apple.*`, slycbar's own, claude's, CloudKit, GeoServices, or a model store such as huggingface, torch, whisper or lm-studio.
4. `redundant`: is or might be unused. An older instance of a daemon that runs more than once with the same command line and holds no open tcp connection; a JetBrains IDE or Android Studio with no settings or cache folder, never opened; a claude transcript over 200M untouched for 14 days; the Claude desktop `vm_bundles` when no process names them; a rust toolchain that is not the default and that no `rust-toolchain` file under `~/Projects` names; the android system images while no emulator runs; an application in `/Applications` or `~/Applications`, not Apple's and not running, whose executable was not read and whose preferences, saved state, caches, container and `Application Support` folder under `~/Library` did not move for 60 days, uninstalled with `brew uninstall --cask <token>` when a homebrew cask installed it, with `rm -rf` otherwise and `sudo rm -rf` when root owns it; a git project folder over 100M under `~/Projects` with no file outside its build folders changed for 60 days, clean, with no stash and every commit on its remote.
5. `data`: loses something. A project folder untouched for 60 days that holds uncommitted, stashed or unpushed work; a folder over 100M directly under `~/Documents`, `~/Desktop` or `~/Downloads` with no file opened or changed for 60 days; a file over 100M in home, outside `Library`, `~/Projects`, hidden folders, `node_modules`, apps and photo libraries, not opened or changed for 60 days. Anonymous docker volumes no container uses, android emulators over 1G with their saved state, installers over 100M in `~/Downloads`.

Transcript folders under `~/.claude/projects` are the working directory with every character that is not a letter or a digit replaced by `-`.

`SPACE_ORPHAN_MIN`, `SPACE_IDLE_HOURS`, `SPACE_STALE_DAYS`, `SPACE_UNUSED_DAYS`, `SPACE_PROJECTS`, `SPACE_RSS_MB`, `SPACE_MIN_FREE_MB`, `SPACE_MAX_MEM`, `SPACE_MAX_CPU` and `SPACE_DU_TIMEOUT` move the thresholds. `disk` and `candidates` walk `$HOME` once with `du -xk -d4` and cache it for 30 minutes in `$TMPDIR/space-n-resources.du`; `SPACE_CACHE_MIN=0` forces a new walk.

`slybar space free` prints one block per group of things that belong together and nothing else, the easiest to remove first and what loses the most last: processes, servers, containers, open applications, sessions, rogue sessions, trash, package caches, browser caches, tool caches, app caches, docker, worktrees, build folders, toolchains and images, applications, browser profiles, transcripts, projects, installers, emulators, docker volumes, files, folders, unpushed projects. A block is `== <group>: <what removing it costs>`, a blank line, then each reason indented as `<why>, <size>` with equal reasons counted as one (`8 × <why>`), directly followed by its own commands and a blank line: one `kill <pid>` for every process, one `rm -rf "<path>"` for every path and each command of a tool, every command on its own line, absolute paths, runnable from any directory, so one thing goes without the rest of its group. Largest first within a group. The group is the sixth column of a `slybar space candidates` row; `--kind` still filters on the first. `slybar space candidates` prints no progress lines, only an error when it cannot read its source.

## Usual suspects

1. OrbStack and Docker: `~/Library/Group Containers/HUAQ24HBR6.dev.orbstack`, volumes, images and build cache. OrbStack is the docker runner; `disk` and `candidates` start it with `orb start` when docker is down, report the size of `data/data.img.raw` and split the volumes into used and unused, anonymous and named. The image is sparse and shrinks once a prune frees its space.
2. Models: `~/.ollama`, `~/.cache/huggingface`, `~/.whisper-models`.
3. Rust `target` and `node_modules` under `~/Projects`.
4. Emulators and simulators: `~/.android/avd`, `~/Library/Android/sdk`, `~/Library/Developer/CoreSimulator`, Xcode derived data.
5. Browser profiles: `~/Library/Caches/ms-playwright`, `ms-playwright-mcp`.
6. Package caches: `~/Library/Caches/go-build`, `~/Library/pnpm`, `~/Library/Caches/pnpm`, `~/go/pkg/mod`, `~/.cargo`, `~/.rustup`, Homebrew.
7. App data: Claude, Superhuman, JetBrains, Slack and Arc under `Application Support`; `~/.claude/projects`; `~/Downloads`; `~/.Trash`.

Processes that have slowed it before: `pnpm dlx` mcp servers and `uvx` children of closed claude sessions, vite dev servers left for days, several claude sessions at once, the Aerial wallpaper and WindowServer, and ollama.

## Rules

1. The answer is the output of `slybar space candidates | slybar space free` and nothing else: no report before it, no free space, no largest consumers, no process list, unless the person asks for them.
2. Each group is handed over as `slybar space free` prints it, in its order: the group and what removing it costs, then each reason as a line with its own commands in a code block below it, never as a numbered list, never merged with another group and never two reasons' commands in one block. Use `slybar space candidates | slybar space free --kind orphan,stale` when the ask is what is left running, `slybar space candidates | slybar space free --kind cache` when the ask is what is safe.
3. Never run a command `slybar space free` prints from `candidates`. A command it prints from `running` is run only after the person has confirmed its group in this conversation, and `pause` and `resume` are the only commands run without that. A process another session started is named with its session folder in the report.
