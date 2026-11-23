---
name: slycbar
description: Drives slycbar, the Claude Code statusline, menu bar tray, desktop widget and code editor on this Mac, through its slybar cli. Use when asked to open a file or folder in the slycbar editor, to show or highlight an exact line or range of a file to the user, to open the tray, to read the Claude accounts with their 5h, 7d and fable limits, the running sessions or the machine's cpu, memory and disk, to switch or refresh a Claude account, or to rebuild and reinstall slycbar.
allowed-tools: Bash(slybar *)
---

# slycbar

One cli, `slybar <command>`. It prints json or plain lines on stdout and errors on stderr.

## Show the user a spot in a file

`slybar edit <path> [line] [end]` opens the file in the slycbar editor and brings it forward.

1. With `line` the cursor lands on that line, centred in the view.
2. With `line` and `end` the whole range is selected, which is how a range is highlighted for the user.
3. A relative path is read from the current directory. A folder opens as the sidebar root.

```
slybar edit src/main.rs 120 134
```

Find the lines first, with a search or a read, then pass the numbers; the editor does not search for text given on the command line.

## Read state

1. `slybar state` prints one json object: `accounts` (each with `email`, `name`, `active`, and `five`, `seven`, `fable` as `{pct, reset}`), `sessions` (each running Claude session with `pid`, `name`, `dir`, `status`, `cpu`, `kb`), `resources.check` (`cpu`, `mem`, `disk`) and `resources.rows`.
2. `slybar refresh [email]` polls the usage of one account, or of all.
3. `slybar resources` rereads cpu, memory and what can be closed; `slybar scan` scans the disk.

## Act

1. `slybar open` shows the tray.
2. `slybar use <email>` switches the signed in Claude account. Only on the user's word.
3. `slybar free <target>...` kills or removes a row the tray lists. Only on the user's word for that exact target.
4. `slybar install` rebuilds and reinstalls the widget, the tray and the editor, and makes the editor the default for text and source files.
5. `slybar plugin install` writes this plugin; `slybar plugin status` says whether the installed one is current.

## The editor

Keys: ⌘K search in every file, ⇧⌘O go to file, ⌘E recent, ⌘L line, ⌘B declaration, ⌘[ and ⌘] back and forward, ⌘1 sidebar, ⇧⌘D inline diff, ⇧⌘M comment to the agent on the spot under the cursor.

The sidebar lists every running Claude session with the files it read or edited. A file the editor cannot name is logged in `~/.cache/slycbar/editor/unknown.log`.

## Language servers

`slybar server <path>` prints the language server the editor uses for that file as json: `server`, `installed`, and the `install` command. `slybar server <path> install` installs it when it is missing, through brew where a formula exists, and prints the same json.

For a file type the catalogue does not know, `server` is `null` and `brew` lists the Homebrew formulae whose name fits the extension. Before opening a file for the user with `slybar edit`, run `slybar server <path> install` so completion, hover, diagnostics and formatting work when it opens. The catalogue is `editor/servers.json`.
