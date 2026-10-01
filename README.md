# herdr-agent-mode

**English** | [한국어](README.ko.md)

A [herdr](https://herdr.dev) plugin that shows, in the agents sidebar, which permission mode each
[Claude Code](https://claude.com/claude-code) pane is running under.

## Why

herdr already shows what an agent is doing — working, idle, blocked. What it cannot show is the
terms it is doing it under. "Claude is working" reads exactly the same whether every edit is being
approved by hand or none of them are, and that difference is the one worth knowing before you look
away from a pane and go do something else.

The mode is also easy to lose track of precisely when it matters. It is a per-session setting you
change with `shift+tab` in the middle of working, it is shown only at the bottom of the pane you are
looking at, and a session you left an hour ago keeps whatever you last set. With a dozen panes, the
one running unattended is not always the one you remember setting that way.

## How it works

- **The value comes from Claude Code, not from herdr.** Claude's hooks carry `permission_mode` on
  stdin, and that is the only place it is published — the status line payload does not include it.
  So the plugin ships a hook script and registers it in `~/.claude/settings.json`.
- **The hook reports the pane itself.** It runs inside the pane, where herdr has already set
  `HERDR_PANE_ID`, `HERDR_SOCKET_PATH` and `HERDR_BIN_PATH`, so it calls
  `herdr pane report-metadata` directly. This plugin therefore needs no herdr event hooks and no
  daemon: a Claude hook *is* the event.
- **Four hooks are registered**, and three of them carry the mode:

  | Hook | When it fires | What it reports |
  |---|---|---|
  | `UserPromptSubmit` | you send a prompt | the mode you are sending it under |
  | `PreToolUse` | before every tool call | the mode in force during the turn |
  | `Stop` | end of the turn | the mode the pane is left in |
  | `SessionEnd` | Claude exits, `/clear`, `/resume` | clears both tokens — the agent is gone |

- **An event that carries no mode leaves the tokens alone.** Claude adds fields over time; a future
  event without the field must not blank a value that is still correct.
- **Every failure is silent.** No herdr, no `jq`, a pane outside herdr, a malformed payload: the
  hook exits 0 and reports nothing. A hook that writes to stderr is a hook you have to think about,
  and nothing here is worth interrupting a session for — at worst the sidebar keeps the last mode.

## What it cannot do

**The sidebar shows the mode as of the pane's last activity, not as of right now.** Claude Code has
no hook event for a mode change, and hooks do not run while a session is idle. So switching mode and
then doing nothing leaves the old value on screen until the next prompt. In practice that window is
short — you change the mode because you are about to ask for something — but it is real, and it is
worth knowing that the sidebar answers "what was it running as" rather than "what is it set to".

`dontAsk` and `bypassPermissions` are not in the `shift+tab` cycle at all; they are chosen when the
session starts (`claude --permission-mode …`, `--dangerously-skip-permissions`, or `defaultMode` in
settings), so for those two there is nothing to lag behind.

## Requirements

- herdr ≥ 0.9.0 (Linux / macOS)
- Claude Code, with a writable `~/.claude/settings.json`
- `bash` and `jq` on the herdr server's `PATH`

## Installation

```sh
herdr plugin install unstable-code/herdr-agent-mode
```

For development, link a local clone instead; the working tree is used directly, so `git pull` is the
update:

```sh
git clone https://github.com/unstable-code/herdr-agent-mode.git
herdr plugin link ./herdr-agent-mode
```

Then register the Claude hooks. This writes into `~/.claude/settings.json`, so it is an action you
run rather than something that happens on its own:

```sh
herdr plugin action invoke unstable-code.herdr-agent-mode.install
```

It leaves every other hook and setting alone, and it owns its entries by a marker comment rather
than by the command string — so installing again after the plugin moved (a linked working tree
today, an installed copy tomorrow) removes the old entry instead of leaving Claude running a command
that is no longer there. The `uninstall` action takes the hooks back out, and `status` says how many
are registered. Running Claude sessions pick up a change without restarting.

The registered command carries its own existence check:

```sh
p='/path/to/herdr-agent-mode/bin/report'; [ -x "$p" ] || exit 0; exec "$p"  # herdr-agent-mode
```

Claude runs a hook command through `/bin/sh`, which fails *before* the script can decline quietly,
so a path that does not exist on this machine would print `No such file or directory` on every turn,
four times over. That is the ordinary case rather than an edge one: `~/.claude/settings.json` is
commonly a symlink into a dotfiles tree shared by several machines, and only one of them ran the
install action.

⚠️ Install the plugin the same way on every machine. `herdr plugin install` puts it under a
directory named from the plugin id alone — the suffix is the first six bytes of `sha256(id)`, with
no commit or hostname in it — so the path is identical everywhere and survives updates. `herdr
plugin link` writes wherever your working tree happens to sit, which is what makes a shared
settings file disagree with itself.

Finally, put a token in the sidebar. Two are published, and a row can use either or both:

| Token | Value | For |
|---|---|---|
| `$mode` | one glyph: `▏▎▍▌▋█` | a row with no width to spare |
| `$mode_label` | a word: `plan`, `deny`, `manual`, `edits`, `auto`, `bypass` | a row that can afford it |

```toml
[ui.sidebar.agents]
rows = [
  ["state_icon", { token = "$mode", fg = "#999999", rules = [
    { equals = "▌", fg = "#AF87FF" },
    { equals = "▏", fg = "#48968C" },
    { equals = "▋", fg = "#FFC107" },
    { equals = "█", fg = "#FF5555", bold = true },
    { equals = "▎", fg = "#FF5555" },
  ] }, "workspace", "tab", "agent"],
  ["terminal_title_stripped"],
]
```

The glyph widths are ordered by how much the mode lets through — `▏` plan reads only, `█` bypass
asks nothing — so the bar says the same thing twice, once in color and once in thickness. That is
not decoration: a sidebar rule matches the token's *own* value, so one shared bar glyph could never
be colored per mode. The redundancy comes free and survives a colorblind eye or a screenshot.

The colors are Claude Code's own, read out of the mode indicator it draws at the bottom of a pane:
accept edits `#AF87FF`, plan `#48968C`, auto `#FFC107` (Claude's `warning` token). Manual has no
color of its own there — it is drawn in the body text color — so it is grey here, and the two modes
you cannot reach by cycling are marked red. Claude's light theme uses `#8700FF`, `#006666` and
`#966C1E` for the first three.

⚠️ Put the token at the **end** of a row unless you have width to spare. When a row does not fit,
herdr turns every flexible token off and then re-enables them from the right, so the leftmost one is
the first to disappear. The example above accepts that risk on purpose: one cell next to the state
icon is worth more than a truncated word at the end.

A mode with no glyph — one Claude adds later — is published as its word under both tokens, so it
shows up as text rather than as an unstyled bar that would read like any other mode.

## Actions

| Action | What it does |
|---|---|
| `install` | registers the Claude hooks in `~/.claude/settings.json` |
| `uninstall` | removes them again |
| `status` | says how many of its hooks are registered, and where |
| `clear` | drops both tokens from every pane that has one |

Each action reports a summary as a herdr notification; the detail goes to `herdr plugin log`.

`clear` is for turning the display off without removing the hooks, and for a pane whose Claude
session ended without its `SessionEnd` hook running — Claude killed rather than exited. A pane that
is closed outright needs nothing: herdr drops the tokens along with the pane.

## Configuration

None. That is a decision, not an omission: a sidebar rule matches the token's own value, so any
setting that changed the shape of that value would silently stop the user's color rules from
matching — and a mode with no rule renders as a plain grey bar, which reads as "manual" rather than
as "broken". Both shapes are published instead, as two tokens, and the row picks the one it wants.

## Verification

Checked on an isolated herdr 0.9.1 server, with the hook script fed the payloads Claude Code sends,
and against a stand-in `settings.json` holding a foreign hook.

| Case | Result |
|---|---|
| Each of Claude's six modes reported | `▍/manual`, `▌/edits`, `▏/plan`, `▋/auto`, `▎/deny`, `█/bypass` |
| An unknown mode (`futureMode`) | published as its own word under both tokens |
| An event carrying no mode (`Notification`) | tokens left unchanged |
| Malformed JSON, empty stdin | tokens unchanged, exit 0, nothing on stderr |
| Run outside herdr (no `HERDR_ENV`) | exit 0, nothing reported |
| `SessionEnd` | both tokens cleared |
| `clear` action | `cleared 1 pane(s)`, both tokens gone |
| `install` over an entry left by an older path | stale entry removed, a foreign hook and herdr's own `SessionStart` untouched, unrelated settings unchanged |
| The registered command run by `/bin/sh` with the script missing | exit 0, nothing printed — the case issue #1 reported |
| The same, with an apostrophe in the plugin path | quoted correctly, runs, and `uninstall` still finds it by its marker |
| `uninstall` | only this plugin's entries gone |
| Against live Claude Code 2.1.285 | `permission_mode` present on `UserPromptSubmit`, `PreToolUse` and `Stop`, absent on `Notification`; a hook added to settings took effect without restarting the session |

## Third-party

This plugin targets herdr, which is licensed under Apache-2.0. No herdr code or binary is
redistributed here. The mode names and the three colors are Claude Code's own values, read from a
running installation and used to match its display; no Claude Code code is included.

## License

[MIT](LICENSE)
