# slycbar

A companion for Claude Code on macOS: a status line, a menu bar tray, a desktop widget, a code editor and a resource guard, driven by one cli, `slybar`. It is a single Swift package that you clone and build yourself.

```
┌──────────────────────────────────────────────────────┬────────────────────────────────────────────────────┬──────────────────────────────────────────────┐
│ dir ~/Projects/acme/widgets                          │ branch feat/1-first-service                        │ issue acme/widgets#1                         │
├─────────────┬───────────┬───────────────────┬────────┴─────┬─────────────┬───────────────┬──────────────┬─┴────────────────────┬─────────┬───────┬───────┤
│ mode auto   │ ctx 82%   │ tok ↓1.5G ↑937k   │ cache 100%   │ cost $447   │ time 27h24m   │ lim 7d 59%   │ lines +11133 -2499   │ rc on   │ sh 0  │ ag 3  │
└─────────────┴───────────┴───────────────────┴──────────────┴─────────────┴───────────────┴──────────────┴──────────────────────┴─────────┴───────┴───────┘
```

## What is in it

| Part | What it does |
| --- | --- |
| Status line | A thin table under the Claude Code prompt: where you are, and one cell per fact about the session. |
| Tray | A menu bar gauge and a popup with every Claude account and its limits, every running session, cpu, memory and disk. |
| Widget | A desktop widget, medium or large, with every running Claude session. |
| Editor | A native code editor with language servers, diff, git, and a sidebar of the files each Claude session touched. Claude Code connects to it with `/ide`. |
| Space | `slybar space` finds what takes disk, memory and cpu and turns what can go into copyable commands. |
| Plugin | Two skills, the `slycbar` MCP server and a hook that refuses a write when the disk is nearly full, installed into Claude Code, Codex, Gemini CLI, opencode, Claude Desktop, ChatGPT desktop or Antigravity. |

## Requirements

- macOS 14 or newer
- A Swift 6 toolchain, from Xcode or the command line tools
- [just](https://github.com/casey/just) and `pnpm`
- `git`, and `claude` for adding accounts and for the Claude Code plugin

## Install

```
git clone https://github.com/SlyOtis/slycbar.git
cd slycbar
cp .env.example .env
just install
slybar plugin install
```

`just install` builds everything and places three apps in `~/Applications`, the cli at `~/.local/bin/slybar`, and a launch agent that keeps the tray running. The cli reads its skills and `editor/servers.json` from the checkout, so keep the clone where it is.

`slybar plugin install` installs for the one host it finds on the machine and asks which when it finds several. A flag picks the host, and several flags can be combined. `slybar plugin status` says whether each installed host matches the checkout.

| Flag | Host | Skills | MCP server | Hook |
| --- | --- | --- | --- | --- |
| `--claude` | Claude Code | the plugin under `~/.slycbar/plugin` | the plugin | the plugin |
| `--codex` | Codex CLI | `~/.agents/skills` | `~/.codex/config.toml` | `~/.codex/hooks.json` |
| `--chatgpt` | ChatGPT desktop | `~/.agents/skills` | `~/.codex/config.toml` | `~/.codex/hooks.json` |
| `--gemini` | Gemini CLI | the extension under `~/.slycbar/gemini` | the extension | the extension |
| `--opencode` | opencode | `~/.config/opencode/skills` | `~/.config/opencode/opencode.json` | none |
| `--desktop` | Claude Desktop | none | `claude_desktop_config.json` | none |
| `--antigravity` | Antigravity | `~/.gemini/config/skills` | `~/.gemini/config/mcp_config.json` | none |

Every other entry in those files is kept. ChatGPT desktop shares its configuration with Codex, so the two flags write the same files. The plan review in the editor works in Claude Code only.

`.env` is read at install time. Every value is optional; `.env.example` lists them with their defaults.

Then add the status line to `~/.claude/settings.json`:

```json
"statusLine": {
  "type": "command",
  "command": "~/.local/bin/slybar statusline",
  "padding": 0,
  "refreshInterval": 5
},
"subagentStatusLine": {
  "type": "command",
  "command": "~/.local/bin/slybar statusline --agents"
}
```

## The cli

```
slybar open                          show the tray
slybar state                         accounts, sessions and resources as json
slybar refresh [email]               read the limits of one account, or of all
slybar use <email>                   switch the signed in Claude account
slybar login                         add an account
slybar forget <email>                drop an account that is not in use
slybar edit <path> [line] [end]      open a file in the editor, on a line or with a range selected
slybar server <path> [install]       the language server for a file, and its install
slybar space <command>               disk, memory and cpu analysis
slybar plugin install [--<host>]     the plugin for a host, see Install
slybar plugin status                 whether each installed host is current
slybar install                       build and install everything
```

## The status line

The first row is where you are: `dir`, `branch`, `issue` when the branch is `feat/<n>-…` or `fix/<n>-…`, and `acct`, a link that opens the tray. The second row is the session: permission mode, context, tokens, cache, cost, time, limits, lines changed, Remote Control, background shells and running agents. Cells switch to short labels and then wrap when the terminal is narrow.

Most cells come straight from the status line input. Tokens are summed from the session transcript and its subagents, counted incrementally and cached under `~/.cache/slycbar/sessions/`. Remote Control, shells and agents are read from Claude Code's session files, which are internal and can change.

`SLYCBAR_MARGIN` sets how many columns are left free at the edges, 4 by default, which matches the padding Claude Code draws around a status line.

## Accounts and the tray

The tray keeps several Claude logins on this machine and switches between them without a new login. Each account shows its limits with the percent used and the time to the reset. A click on another account switches Claude Code to it; nothing restarts and no session is lost.

Every login is kept in the macOS keychain under the service `slycbar` and never leaves the machine. The limits are read from the same endpoints Claude Code uses, which are not documented and can change.

## The editor

`slybar edit <path> [line] [end]` opens a file or a folder. `just install` also makes the editor the default for text and source files.

- ⌘K searches every file, ⇧⌘O goes to a file, ⌘L to a line, ⌘B to a declaration.
- ⇧⌘D shows an inline diff; a git panel covers staging, commits, branches and stash.
- Language servers give completion, hover, diagnostics and formatting. `slybar server <path> install` installs the one a file needs.
- With a project folder open, `/ide` in Claude Code connects to the editor. Proposed edits open as a diff to accept or reject.
- Markdown, html and svg files have a live preview beside the code.

The editing surface is a web page built with CodeMirror and Vue under `editor/`. The components in `editor/components-nimtech/` are copied from `@nimling/components-nimtech`, MIT licensed, see the `NOTICE` there.

## Space and the guard

```
slybar space all                 disk, then memory and cpu
slybar space candidates          one row per thing that can go
slybar space running             what runs now
slybar space pause               stop every claude session but the one asking
slybar space resume              continue what pause stopped
```

`slybar space candidates | slybar space free` turns the list into a reason and a copyable command for each row. Nothing is removed for you. The plugin's hook refuses a write when the disk is under its limit.

## Development

```
just build        # release build
just test         # swift test
just dev state    # run the cli without installing
```

## License and credit

MIT, see [LICENSE](LICENSE). Made by Martin Ottersland ([SlyOtis](https://github.com/SlyOtis)). Copy it, use it and change it, and keep the credit. Issues and pull requests that make a part reusable on its own are welcome.
