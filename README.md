# herdr-agent-mode

**English** | [한국어](README.ko.md)

A [herdr](https://herdr.dev) plugin that shows, in the agents sidebar, which permission mode each
[Claude Code](https://claude.com/claude-code) pane is running under — and which agent (Build, Plan,
…) each [opencode](https://opencode.ai) pane is — and which model each of them is running on.

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
- **Five hooks are registered**; three carry the mode, and one the model:

  | Hook | When it fires | What it reports |
  |---|---|---|
  | `SessionStart` | Claude starts, `/clear`, `/resume` | the model the session starts on |
  | `UserPromptSubmit` | you send a prompt | the mode you are sending it under |
  | `PreToolUse` | before every tool call | the mode in force during the turn |
  | `Stop` | end of the turn | the mode the pane is left in, and the model that wrote the reply |
  | `SessionEnd` | Claude exits, `/clear`, `/resume` | clears every token — the agent is gone |

- **The model after `SessionStart` comes from the transcript.** No other hook carries it, but every
  assistant message in the transcript records the model that wrote it. Claude writes the turn's reply
  there only after the `Stop` hook returns, so the hook reports the mode, then reads the reply's model
  in the background once it lands (within a fraction of a second; it gives up after three). The end
  of the file is read, not the whole of it — a long session's transcript runs to tens of megabytes.
- **The model is shortened when its shape is known**: `claude-opus-5-5` → `opus 5.5`,
  `claude-haiku-4-5-20251001` → `haiku 4.5`. Any other id — opencode's local models, another
  provider's — is published as it is, rather than shortened by a guess.
- **A field an event does not carry is left alone.** `SessionStart` has no mode and most hooks have no
  model, and neither may blank the other. Claude adds fields over time, too; a future event without
  one must not blank a value that is still correct.
- **Every failure is silent.** No herdr, no `jq`, a pane outside herdr, a malformed payload: the
  hook exits 0 and reports nothing. A hook that writes to stderr is a hook you have to think about,
  and nothing here is worth interrupting a session for — at worst the sidebar keeps the last mode.

### opencode

opencode has **agents** where Claude has permission modes (Build and Plan by default). They are
published under the same two tokens:

| Agent | `$mode` | `$mode_label` |
|---|---|---|
| `plan` | `▏` — reads only, like Claude's plan | `plan` |
| `build` | `▍` — asks for permission, like Claude's manual | `build` |
| anything else (a custom agent) | its name | its name |

- **It is an opencode 2.x TUI plugin**: `opencode/tui.js`, registered in the `"plugins"` list of
  opencode's `cli.json`. Not a server hook such as `chat.message`, because in the full TUI the server
  may be shared or run in a worker that cannot tell which pane it serves; herdr's own opencode
  integration reports from its TUI plugin for the same reason.
- **The value is the selected session's agent** (`api.data.session.get(id).agent`). When it changes,
  the plugin runs `bin/publish`, which reports through the same `lib.sh` code as the Claude hook — the
  glyph table, the token names and the sequence rule exist once for both agents.
- **The model is the same session's** (`.model.id`), published as `$model`. The TUI can also read the
  prompt's current model selection, but the agent lags (below), and a model that did not would pair
  the two in a way no message ran under.
- **Every token is cleared when opencode exits**, and on the home screen, where no session is open and
  there is nothing to report.

## What it cannot do

**The sidebar shows the mode as of the pane's last activity, not as of right now.** Claude Code has
no hook event for a mode change, and hooks do not run while a session is idle. So switching mode and
then doing nothing leaves the old value on screen until the next prompt. In practice that window is
short — you change the mode because you are about to ask for something — but it is real, and it is
worth knowing that the sidebar answers "what was it running as" rather than "what is it set to".

`dontAsk` and `bypassPermissions` are not in the `shift+tab` cycle at all; they are chosen when the
session starts (`claude --permission-mode …`, `--dangerously-skip-permissions`, or `defaultMode` in
settings), so for those two there is nothing to lag behind.

**opencode lags the same way.** It records the agent on the session when a message is sent; cycling
with `shift+tab` only changes what the prompt shows, and the TUI plugin API has no way to read that
selection (it has one for the model and variant). A newly chosen agent appears in the sidebar with the
next message.

**The model lags by a turn's length.** `/model` in Claude, like a model change in opencode, shows up
when the first turn under the new model has ended (Claude) or its message has been sent (opencode) —
both agents record the model on what it wrote, and neither has an event for the switch itself.

## Requirements

- herdr ≥ 0.9.0 (Linux / macOS)
- Claude Code, with a writable `~/.claude/settings.json` — and/or
- opencode 2.x, with a writable `cli.json` (in `$OPENCODE_CONFIG_DIR` or `~/.config/opencode/`)
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
than by the command string, so installing again replaces an older entry of its own instead of adding
a second one. The `uninstall` action takes the hooks back out (run it before `herdr plugin
uninstall`, which does not), and `status` shows the link and the registered command. Running Claude sessions pick up a change without restarting.

The same action registers opencode: it adds a link in the plugin's state directory
(`…/unstable-code.herdr-agent-mode/opencode`) to the `"plugins"` list in `cli.json`, and the link
points at the installation's `opencode/` — for the same reason as the Claude link described below.
Every other entry, herdr's own `./herdr-opencode` included, is left alone. A running opencode picks it
up on its next start. Whichever agent has no config file is skipped; the action fails only when
neither has one. A `cli.json` with comments (JSONC) is not touched, because jq cannot keep its
formatting — the action prints the path to add by hand instead. `cli.json` is per machine, so run the
action on every machine that uses opencode.

The registered command names a link, not the installation, and carries its own existence check:

```sh
p="$HOME"'/.local/state/herdr/plugins/unstable-code.herdr-agent-mode/bin/report'; [ -x "$p" ] || exit 0; exec "$p"  # herdr-agent-mode
```

The link lives in the plugin's state directory, which herdr names from the plugin id alone, and
points at the `bin/` directory of whichever installation is current. Since herdr 0.9.5 every
install and `herdr plugin update` goes into a new directory (`…/github-installations/<id>-<hash>/<pid>-<n>/`), so
a command naming the installation would stop working at the first update — silently, because of the
check below. The install action creates the link; a `[[startup]]` hook moves it to the new
installation on the next server start. `settings.json` is not touched by either, and is only rewritten
by the install action when its entries actually change.

Claude runs a hook command through `/bin/sh`, which fails *before* the script can decline quietly,
so a path that does not exist on this machine would print `No such file or directory` on every turn,
once for each hook. That is the ordinary case rather than an edge one: `~/.claude/settings.json` is
commonly a symlink into a dotfiles tree shared by several machines, and only one of them ran the
install action.

Because the link path depends only on the plugin id and your home directory, a `settings.json` shared
between machines names the same path on all of them, however each one installed the plugin. Run
the install action on one of them; every other machine sharing the file gets its link from the
startup hook the next time its herdr server starts. Upgrading from a version before the link, or
from one that registered fewer hooks (`SessionStart` arrived with the model): run the install action
once more — it replaces the old entries, and until then the startup hook shows a notification saying
so.

Finally, put the tokens in the sidebar. Three are published, and a row can use any of them:

| Token | Value | For |
|---|---|---|
| `$mode` | one glyph: `▏▎▍▌▋█` | a row with no width to spare |
| `$mode_label` | a word: `plan`, `deny`, `manual`, `edits`, `auto`, `bypass` | a row that can afford it |
| `$model` | the model: `opus 5.5`, `qwen3.6-35b-a3b` | a row with room for a name |

```toml
[ui.sidebar.agents]
rows = [
  ["state_icon", { token = "$mode", fg = "#999999", rules = [
    { equals = "▌", fg = "#AF87FF" },
    { equals = "▏", fg = "#48968C" },
    { equals = "▋", fg = "#FFC107" },
    { equals = "█", fg = "#FF5555", bold = true },
    { equals = "▎", fg = "#FF5555" },
  ] }, "workspace", "tab", "agent", "$model"],
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
| `install` | registers the Claude hooks in `~/.claude/settings.json` and the TUI plugin in opencode's `cli.json` |
| `uninstall` | removes them again |
| `status` | says how many Claude hooks are registered, whether opencode is, and where |
| `clear` | drops this plugin's tokens from every pane that has one |

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
| Install over an entry that named an installation directly (herdr 0.9.5) | old entry replaced by `p="$HOME"'/…/bin/report'`, the `bin` link pointing at the installation, a foreign hook and other settings untouched |
| Install again with nothing changed | `settings.json` not rewritten (same mtime) |
| "Update" on a machine without the link: the plugin re-registered from a second directory, the link deleted, server restarted | the `[[startup]]` hook made the link to the new `bin/` from the entries in `settings.json`, which stayed byte-identical |
| An entry from before the link, then a server start | link made, and one notification asking for the install action; no notification once the entry is current |
| The first installation deleted, then the registered command run by `/bin/sh` with a `plan` payload | `▏`/`plan` reported through the link (#2) |
| `uninstall`, then a restart | link removed with the hooks; the startup hook did not create it again |
| A state directory outside `$HOME` | the command is written with the absolute path instead |
| Against live Claude Code 2.1.285 | `permission_mode` present on `UserPromptSubmit`, `PreToolUse` and `Stop`, absent on `Notification`; a hook added to settings took effect without restarting the session |
| install, install again, uninstall on a stand-in `cli.json` holding herdr's entry | link entry appended; the second run does not rewrite the file; after uninstall the content equals the original; `./herdr-opencode` untouched |
| A stale entry left under another state directory | swept by install, leaving only the current link |
| A `cli.json` with comments (JSONC) | not touched; the path to add by hand is printed |
| A machine with only opencode / with neither | Claude skipped, opencode registered / exit 1 |
| The opencode link deleted, then the startup command (`hooks --relink`) | link made again from the entry in `cli.json` |
| Against live opencode 2.2.6 TUI | no tokens on the home screen; a message under Build → `▍`/`build`; `shift+tab` alone → unchanged; a message under Plan → `▏`/`plan`; opencode exited → both tokens cleared. A plugin directory registered by absolute path loads |
| Model ids shortened | `claude-opus-5-5` → `opus 5.5`, `claude-opus-5` → `opus 5`, `claude-haiku-4-5-20251001` → `haiku 4.5`, `claude-opus-5-5[1m]` → `opus 5.5[1m]`; `qwen3.6-35b-a3b`, `gpt-5.1`, `claude-3-5-sonnet-20241022` unchanged |
| `SessionStart` (model, no mode), then `PreToolUse` (mode, no model) | the first reports `$model` alone, the second the mode alone; neither clears the other |
| `install` over the four hooks of the previous version, and a startup before it | a `SessionStart` entry added; until then the startup hook asks for the install action |
| Against live Claude Code 2.1.330 | `SessionStart` carries `model` and no `permission_mode`; `Stop` carries neither model nor the turn's reply in the transcript — the reply lands about 0.1s after the hook starts. A new session shows `haiku 4.5` from `SessionStart`; after `/model sonnet` the first turn's end brings `sonnet 5.5`; `/exit` clears all three tokens |
| Against live opencode 2.2.6 TUI | a message → `▍`/`build` with `qwen3.6-35b-a3b`; exit clears all three. A switch to another model was not tried live: the only other models configured were paid ones |
| `clear` action | `$model` dropped along with the mode tokens, including on a pane carrying only `$model` |

## Third-party

This plugin targets herdr, which is licensed under Apache-2.0. No herdr code or binary is
redistributed here. The mode names and the three colors are Claude Code's own values, read from a
running installation and used to match its display; no Claude Code code is included.

## License

[MIT](LICENSE)
