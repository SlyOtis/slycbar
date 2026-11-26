---
name: slycbar
description: Drives slycbar, the Claude Code statusline, menu bar tray, desktop widget and Slyed, its code editor, on this Mac, through its slybar cli and its MCP tools. Use when asked to open a file or folder in Slyed, to show or highlight an exact line or range of a file to the user, in plan mode to put the intended changes before the user as real proposed file contents for review in Slyed, wait for the review, read back their decisions, comments, questions and guidance and revise the plan, to compare two files side by side, to open the tray, to read the Claude accounts with their 5h, 7d and fable limits, the running sessions or the machine's cpu, memory and disk, to switch or refresh a Claude account, or to rebuild and reinstall slycbar.
allowed-tools: Bash(slybar *), mcp__plugin_slycbar_slycbar__review_open, mcp__plugin_slycbar_slycbar__review_status, mcp__plugin_slycbar_slycbar__review_wait
---

# slycbar

One cli, `slybar <command>`. It prints json or plain lines on stdout and errors on stderr.

## Show the user a spot in a file

Slyed: see every change before it lands.

`slybar edit <path> [line] [end]` opens the file in Slyed and brings it forward.

1. With `line` the cursor lands on that line, centred in the view.
2. With `line` and `end` the whole range is selected, which is how a range is highlighted for the user.
3. A relative path is read from the current directory. A folder opens as the sidebar root.

```
slybar edit src/main.rs 120 134
```

Find the lines first, with a search or a read, then pass the numbers; Slyed does not search for text given on the command line.

## Put a plan of changes up for review

A plan is real proposed file contents, never prose alone. Slyed, the slycbar editor, shows it in its main area: a list of every change with its why, counts, status and feedback, and a diff of each change, the current file on the left and the proposed contents on the right, both read only. Nothing touches the target files; the user decides, comments and asks, Slyed writes it all into the plan file, and the agent revises or applies what was accepted.

### In plan mode

1. Research, then put the intended changes up with the slycbar MCP tool `review_open` (`mcp__plugin_slycbar_slycbar__review_open`): `title`, and `changes`, each with `title`, `why`, the absolute target `path` and the full proposed `contents`. slycbar writes each proposed file beside the plan file under `~/.cache/slycbar/plans/` and returns the plan path. Without the MCP tool: `slybar review - <<'EOF'` with the same json on stdin.
2. Wait with `review_wait` and the plan path (`slybar review <plan.json> wait [seconds]`), up to 600 seconds by default and 3600 at most. It returns when the user sends the review, with `state` `sent` or `approved`, or with `waited` set when nothing came.
3. On `sent`, read every comment with `review_status` (`slybar review <plan.json> status`). Answer each question in that comment's `answer` field, rewrite the proposals, and call `review_open` again with the same `plan` path, the revised `changes`, and the `comments` with their answers (`slybar review <plan.json> put` with the plan on stdin). The round goes up by one and the state back to `open`; a change whose proposed contents did not change keeps its status. Then wait again.
4. Call ExitPlanMode only when every change is accepted or the state is `approved`. The plugin's hook on ExitPlanMode refuses it while the review is open, with the counts and what to do; when the session never put a plan up, it refuses once with a reminder and lets the second call through, for a plan that changes no file. `SLYCBAR_PLAN=off` in the environment or in the checkout's `.env` turns the hook off.
5. Apply exactly what was accepted.

The session is found by itself: `review_open` and `slybar review` walk up their parent processes to the Claude Code session and write its id as `session` and its folder as `dir`.

### The plan file

```
{
  "title": "Rename the config loader",
  "session": "<session id, name, pid or messaging socket path>",
  "dir": "/abs/project",
  "state": "open",
  "round": 1,
  "comments": [{"text": "keep the old flag one release", "question": false, "change": 2}],
  "changes": [
    {
      "title": "Read the config from one place",
      "why": "two loaders read the same file differently",
      "path": "/abs/path/to/target.yml",
      "proposed": "/abs/plan/folder/proposed/1-target.yml",
      "base": "/abs/path/to/left.yml",
      "status": "pending",
      "comments": [
        {"side": "proposed", "line": 12, "end": 14, "text": "this drops the env override"},
        {"side": "change", "text": "why not in the loader itself?", "question": true, "answer": "the loader is shared with the cli"}
      ]
    }
  ],
  "run": {"pid": 123, "log": "/abs/plan/folder/revise.log", "dir": "/abs/project", "started": "…", "code": 0}
}
```

1. `path` and `proposed` are absolute and `proposed` exists; a change given with `contents` gets its `proposed` file written. `base` is optional: the left side when it is not the target's current contents. A target that does not exist yet is shown against an empty left side.
2. `status` is `pending`, `accepted` or `rejected`, set by the user.
3. A change's `comments` hold line comments (`side` `base` or `proposed`, `line`, `end`) and feedback on the change as a whole (`side` `change`). The top level `comments` hold guidance and questions on the plan as a whole, with `change` naming the change it was written at. Any comment may carry `question` true, which wants an `answer`, and `sent` true once it went out.
4. `state` is `open` while the user reviews, `sent` when the review went to the session, `revising` while a separate run revises the plan, and `approved` when every change was accepted at send. `run` records the last revise run.
5. Rewriting the plan file while it is open makes Slyed read it again within five seconds.

### In Slyed

A review opens in the diff: the current file on the left and the proposed on the right fill the area, with every unchanged line above and below the region in focus blurred, and next and previous in the walkthrough move the focus and the blur to the next changed region. Below them, across the full width, the review panel shows the change's number, title, path and why with its comments, and holds the text field (↵ or the arrow saves it in the plan) and every control as an icon: lines, change or plan for what the text is about, question, previous and next, accept and reject, walkthrough, the list toggle, send to session, revise with a run, and close. The list, behind its toggle, shows every change with its why, counts, status and comments; picking one opens its diff. Nothing is sent until the user sends: the paper plane sends every unsent comment and the status of every change to the plan's session through its messaging socket, the play button starts a separate Claude Code run in the plan's `dir` that revises the plan file and its proposed files and nothing else, logged to `revise.log` beside the plan.

Keys: ⇧⌘R list or diff; ⌥⌘] and ⌥⌘[ next and previous change, or changed region in the walkthrough; ⌥⌘W the walkthrough through every changed region; ⌥⌘Y accept, ⌥⌘N reject; ⇧⌘M comment on the selected lines; ⌥⌘/ mark the next comment as a question; the Review menu also holds Feedback on Change, Guidance for the Plan, Send Review to Session and Revise with a New Run.
## Compare two files

`slybar compare <path> <path>` opens the two files side by side, the first on the left, read only, with next and previous over the differences. A relative path is read from the current directory.

## Read state

1. `slybar state` prints one json object: `accounts` (each with `email`, `name`, `active`, and `five`, `seven`, `fable` as `{pct, reset}`), `sessions` (each running Claude session with `pid`, `name`, `dir`, `status`, `cpu`, `kb`), `resources.check` (`cpu`, `mem`, `disk`) and `resources.rows`.
2. `slybar refresh [email]` polls the usage of one account, or of all.
3. `slybar resources` rereads cpu, memory and what can be closed; `slybar scan` scans the disk.

## Act

1. `slybar open` shows the tray.
2. `slybar use <email>` switches the signed in Claude account. Only on the user's word.
3. `slybar free <target>...` kills or removes a row the tray lists. Only on the user's word for that exact target.
4. `slybar install` rebuilds and reinstalls the widget, the tray and Slyed, and makes Slyed the default for text and source files.
5. `slybar plugin install` installs the skills, the guard hook and the `slycbar` MCP server (`slybar mcp`, stdio) with `review_open`, `review_status` and `review_wait` for the one host it finds, and lists the hosts when it finds several; `--claude`, `--codex`, `--gemini`, `--opencode`, `--desktop`, `--chatgpt` and `--antigravity` pick the host. Claude Code gets the plugin with the hook on SessionStart, PreToolUse, PostToolUse and ExitPlanMode; Codex and ChatGPT desktop get `~/.agents/skills`, `~/.codex/config.toml` and `~/.codex/hooks.json`; Gemini CLI an extension with its hooks; opencode and Antigravity the skills and the server; Claude Desktop the server. `slybar plugin status` says whether each installed host is current.

## Slyed

Keys: ⌘K search in every file, ⇧⌘O go to file, ⌘E recent, ⌘L line, ⌘B declaration, ⌘[ and ⌘] back and forward, ⌘1 sidebar, ⇧⌘D inline diff, ⇧⌘M comment to the agent on the spot under the cursor.

The sidebar lists an open review plan with its state, round, totals and the status, line counts and comments of each change, then every running Claude session with the files it read or edited. A file Slyed cannot name is logged in `~/.cache/slycbar/editor/unknown.log`.

## Language servers

`slybar server <path>` prints the language server Slyed uses for that file as json: `server`, `installed`, and the `install` command. `slybar server <path> install` installs it when it is missing, through brew where a formula exists, and prints the same json.

For a file type the catalogue does not know, `server` is `null` and `brew` lists the Homebrew formulae whose name fits the extension. Before opening a file for the user with `slybar edit`, run `slybar server <path> install` so completion, hover, diagnostics and formatting work when it opens. The catalogue is `editor/servers.json`.
