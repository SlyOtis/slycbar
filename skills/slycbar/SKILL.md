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

A plan is real proposed file contents, never prose alone. Slyed, the slycbar editor, cuts every change into its diff hunks with git and shows them in one native diff view, side by side or as a single column, with the review panel below it. Nothing touches the target files; the user accepts or rejects each hunk, with or without a comment, Slyed writes it all into the plan file, and the agent revises or applies what was accepted.

### In plan mode

1. Research, then put the intended changes up with the slycbar MCP tool `review_open` (`mcp__plugin_slycbar_slycbar__review_open`): `title`, and `changes`, each with `title`, `why`, the absolute target `path` and the full proposed `contents`. slycbar writes each proposed file beside the plan file under `~/.cache/slycbar/plans/` and returns the plan path. Without the MCP tool: `slybar review - <<'EOF'` with the same json on stdin.
2. Wait with `review_wait` and the plan path (`slybar review <plan.json> wait [seconds]`), up to 600 seconds by default and 3600 at most. It returns when the user sends the review, with `state` `sent` or `approved`, or with `waited` set when nothing came.
3. On `sent`, read every comment with `review_status` (`slybar review <plan.json> status`). Answer each question in that comment's `answer` field, rewrite the proposals, and call `review_open` again with the same `plan` path, the revised `changes`, and the `comments` with their answers (`slybar review <plan.json> put` with the plan on stdin). The round goes up by one and the state back to `open`; a change whose proposed contents did not change keeps its status. Then wait again.
4. Call ExitPlanMode only when every change is accepted or the state is `approved`. The plugin's hook on ExitPlanMode refuses it while the review is open, with the counts and what to do; when the session never put a plan up, it refuses once with a reminder and lets the second call through, for a plan that changes no file. `SLYCBAR_PLAN=off` in the environment or in the checkout's `.env` turns the hook off.
5. Apply exactly what was accepted.
6. When the user asks to see only some of the changes, read the file `review_status` names as `hunks`, a jsonl with one line per hunk (`hunk`, `change`, `path`, `side`, `line`, `end`, `added`, `removed`) that Slyed writes within seconds of opening. Work out which hunks they mean from the two files at those lines, then call `review_open` with the plan path and either `focus`, a list of hunk numbers, or `groups`, each with `title`, `hunks` and `collapsed`. Hunks in focus or in an open group are shown open and want a verdict; every other hunk is one collapsed line, and the review is done when the hunks in focus are decided.
7. When the user asks for single view or side by side, call `review_open` with the plan path and `view` `single` or `sides`.
8. When the user asks to compare two files, two versions of an api or two applications, put the comparison up the same way: one change per pair of files with `base` the left file, `proposed` the right file, `path` the right file and no `contents`, after bringing both sides to the same shape where that removes noise, such as sorted keys and one formatting for json, and for two folders one change per file that differs. Then sort the hunks into `groups` by what they mean, collapse the groups the user did not ask about, and send them.
9. The user can select lines in the diff, in one or several hunks, and ask about them. The question arrives as a message with the path, the lines, the selected rows and the commits that touched them, and in a review also as a comment on that change with `question` true, `side`, `line` and `end`. Answer it by setting `answer` on that comment and calling `review_open` with the plan path and that change as only its `path` and its `comments`; Slyed shows the question and the answer under those lines. A comment of your own with `side`, `line`, `end` and `text` is shown the same way, as a note under the lines it is about.

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
6. `focus` is a list of hunk numbers such as `1.4`; `groups` is a list of `{title, hunks, collapsed}` shown in that order in place of the file order, with the hunks in no group last under Everything else, collapsed. An empty `focus` and no `groups` puts every hunk in focus.
7. `view` is `sides`, the default, or `single`. A change's `diff` lists how git aligns it: one of `histogram` (the default), `patience`, `minimal`, `myers`, and any of `ignore-all-space`, `ignore-space-change`, `ignore-space-at-eol`, `ignore-blank-lines`, `ignore-cr-at-eol`.

### In Slyed

A review opens in the diff view on the first pending hunk in focus: the hunk in focus is drawn at full strength and the others dimmed, each under a head with its number, status and comment, grouped under its file or its group. Below it the review panel shows the hunk's number, the change's title and path, the why of that hunk, the comments, a text field for a comment on the hunk, previous and next, the single and side by side switch, and reject and accept. A verdict moves to the next pending hunk in focus; when the last one is decided the review goes back to the session by itself, `approved` when every hunk in focus was accepted and `sent` otherwise.

The panel under a diff is the one input for everything sent to the agent: in a review it switches between review, where the text is a comment that goes with accept or reject, and ask, where the text is a question; under a comparison or a file diff, and under the editor after Send to agent, it asks about the selected lines, shown as a tag, or about the change in focus.

Keys: ⇧⌘R open the review; ⌥↓ and ⌥↑, or ⌥⌘] and ⌥⌘[, next and previous hunk; accept, reject and ask are `accept`, `reject` and `ask` in `~/.slycbar/settings.json`, by default `cmd+return`, `opt+return` and `ctrl+return`; ⌘+ and ⌘− text size.

## Compare two files

`slybar compare <path> <path>` opens the two files in the diff view side by side, the first on the left, read only, with next and previous over the differences and the hunks out of focus blurred. A relative path is read from the current directory.

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

Slyed is native: the editor, the diff view and the previews are AppKit and SwiftUI views. A markdown, html or svg file opens with its preview beside the code, and images, pdf, video and audio open in place.

Keys: ⌘K search in actions, files, symbols and text, ⇧⌘O go to file, ⌘E recent, ⌘L line, ⌘B declaration, ⌘[ and ⌘] back and forward, ⌘1 sidebar, ⌘F find, ⇧⌘D inline diff with the change marks in the gutter, ⇧⌘M comment to the agent on the selected lines.

1. Selecting lines shows a Send to agent button; the comment goes to the agent on that file with the path, the line range, the selected code and the uncommitted change there.
2. The inline diff marks every change in the gutter while the file stays editable, and a click on a mark reverts or keeps that change. Side by side shows the base read only on the left and the file editable on the right.
3. A Claude Code proposal from `/ide` opens editable with its changes marked; accept returns the text as edited.
4. Editing keys: ⌘D duplicate line, ⌘Y delete line, ⇧⌥↑ and ⇧⌥↓ move lines, ⌘/ comment, ⌥↑ and ⌥↓ grow and shrink the selection, ⌃G add the next occurrence, ⌃⌘G every occurrence, ⌘-click another caret, ⌃− and ⌃= fold and unfold, ⌥⌘L format.
5. The zoom control at the bottom right sets the text size per file type and stores it in `~/.slycbar/settings.json`.

The sidebar lists an open review plan with its state, round, totals and the status, line counts and comments of each change, then every running Claude session with the files it read or edited. File and symbol lookup run from an index at `~/.cache/slycbar/editor/index.sqlite`. A file type Slyed has no rules for is logged in `~/.cache/slycbar/editor/unknown.log`.

## Language servers

`slybar server <path>` prints the language server Slyed uses for that file as json: `server`, `installed`, and the `install` command. `slybar server <path> install` installs it when it is missing, through brew where a formula exists, and prints the same json.

For a file type the catalogue does not know, `server` is `null` and `brew` lists the Homebrew formulae whose name fits the extension. Before opening a file for the user with `slybar edit`, run `slybar server <path> install` so completion, hover, diagnostics and formatting work when it opens. The catalogue is `editor/servers.json`; an entry of the same name in `~/.slycbar/servers.json` replaces it and a new name adds a server.
