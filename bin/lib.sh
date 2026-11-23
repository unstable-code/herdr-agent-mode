#!/usr/bin/env bash
# Shared helpers for bin/report (the Claude hook entry point), bin/state (the herdr event hook),
# bin/publish (opencode's), bin/hooks and bin/clear.

herdr=${HERDR_BIN_PATH:-herdr}
source_id=unstable-code.herdr-agent-mode
# The $state_* tokens are written under their own source, and only under it — the sequence rule (see
# publish) would otherwise let a status report and a mode report drop each other. Between two status
# reports, dropping the older is exactly right.
state_source_id=$source_id.state
glyph_token=mode
label_token=mode_label
model_token=model
effort_token=effort
# One token per agent status (#5), and exactly one of them is set on a pane at a time. A sidebar rule
# reads only its own token's value, so the effort glyph cannot be colored by the status it sits
# beside — but five tokens, each colored in the row, can: the one that is set is the one that shows.
statuses=(working blocked "done" idle unknown)
state_tokens=("${statuses[@]/#/state_}")
# shellcheck disable=SC2034  # bin/hooks uses it; this file is sourced, not run.
settings_file="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/settings.json"

# Where Claude's hooks point: bin/report through a symlink to this bin/ directory, kept in the
# plugin's state directory. herdr names that directory from the plugin id alone, so it is the same
# path on every machine and across updates — unlike the installation itself, which since herdr 0.9.5
# is a new directory on every install and update (issue #2). The link is to the directory, not to
# the script, because bin/report finds lib.sh next to its own path. The install action places the
# link; the [[startup]] hook moves it after an update.
#
# The fallback copies herdr's layout (config/io.rs state_dir + plugin_paths.rs plugin_state_dir), for
# running bin/hooks by hand. It holds only while the shell and the herdr server agree on
# XDG_STATE_HOME; the actions get the real directory from herdr.
state_dir=${HERDR_PLUGIN_STATE_DIR:-${XDG_STATE_HOME:-$HOME/.local/state}/herdr/plugins/$source_id}
# shellcheck disable=SC2034  # bin/hooks uses it.
bin_link="$state_dir/bin"

# opencode (#3): an opencode 2.x TUI plugin in this installation's opencode/ directory, registered in
# opencode's cli.json "plugins" list. The registered path is a link here for the same reason as
# bin_link — an update moves the installation, the link follows it. The config directory is found the
# way herdr's own opencode integration finds it (src/integration/env.rs opencode_dir).
# shellcheck disable=SC2034  # bin/hooks uses them.
opencode_cli="${OPENCODE_CONFIG_DIR:-${XDG_CONFIG_HOME:-$HOME/.config}/opencode}/cli.json"
# shellcheck disable=SC2034
opencode_link="$state_dir/opencode"

# This plugin has no config file, and that is a decision rather than an omission. A sidebar rule
# matches the token's own value, so any setting that changed the shape of that value would silently
# stop the user's color rules from matching — a failure that looks exactly like "the mode is grey".
# Both shapes are published instead, as two tokens, and the row picks the one it wants.

# Millisecond clock. herdr keeps the highest sequence per source, so a hook that finishes late
# cannot overwrite a newer mode with an older one. EPOCHREALTIME is a bash builtin, which matters:
# this runs before every tool call, and `date` would be one more process each time.
now_ms() {
    local t=${EPOCHREALTIME/[.,]/}
    if [ -n "$t" ]; then printf '%s\n' "${t:0:${#t}-3}"; else date +%s%3N; fi
}

# A one-cell bar, for a sidebar row with no space to spare.
#
# Each mode gets a *different* glyph, and that is not decoration: a sidebar rule reads the value of
# the token it is attached to, so a bar that was "▌" in every mode could never be colored per mode.
# The widths are ordered by how much the mode lets through — plan reads only, bypass asks nothing —
# so the bar carries the same meaning twice, once in color and once in thickness. That redundancy is
# what makes it survive a colorblind eye, a washed-out terminal, or a screenshot.
#
# A mode with no glyph here falls back to its word: an unknown mode is worth seeing as text, because
# a glyph nobody wrote a rule for would render as a plain grey bar and read as a mode that is fine.
mode_glyph() {
    case "$1" in
        plan) printf '▏\n' ;;              # read-only (Claude's plan, and opencode's Plan agent)
        dontAsk) printf '▎\n' ;;           # auto-denies
        default | build) printf '▍\n' ;;   # asks every time (Claude's manual, opencode's Build agent)
        acceptEdits) printf '▌\n' ;;       # edits go through
        auto) printf '▋\n' ;;              # a classifier decides
        bypassPermissions) printf '█\n' ;; # nothing is asked
        *) mode_label "$1" ;;
    esac
}

# The same mode as a word. Claude reports the mode its own UI labels "Manual" as `default`, which is
# why that arm is not called manual here.
mode_label() {
    case "$1" in
        default) printf 'manual\n' ;;
        acceptEdits) printf 'edits\n' ;;
        bypassPermissions) printf 'bypass\n' ;;
        dontAsk) printf 'deny\n' ;;
        *) printf '%s\n' "$1" ;;
    esac
}

# The model as a short name: `claude-<family>-<major>[-<minor>][-<date>][<suffix>]` becomes
# `<family> <major>[.<minor>][<suffix>]`. Any other id is published as it is — one shortened by a
# guess could name the wrong model.
model_label() {
    if [[ $1 =~ ^claude-([a-z]+)-([0-9]+)(-([0-9]{1,2}))?(-[0-9]{8})?(\[[^]]*\])?$ ]]; then
        printf '%s %s%s%s\n' "${BASH_REMATCH[1]}" "${BASH_REMATCH[2]}" \
            "${BASH_REMATCH[4]:+.${BASH_REMATCH[4]}}" "${BASH_REMATCH[6]}"
    else
        printf '%s\n' "$1"
    fi
}

# effort_glyph <effort> <status>: the shapes are Claude Code's own (2.1.330); opencode's variants share
# the level names. `none` takes the empty circle neither Claude nor herdr uses. No effort falls back
# to state_icon's shape for the status, so an agent this plugin knows nothing about looks as before.
# An unknown level is its word: a glyph nobody wrote down would pass for one that means something.
effort_glyph() {
    case "$1" in
        low) printf '○\n' ;;
        medium) printf '◐\n' ;;
        high) printf '●\n' ;;
        xhigh) printf '◉\n' ;;
        max) printf '◈\n' ;;
        none) printf '◌\n' ;;
        "" | default)
            case "$2" in
                idle) printf '○\n' ;;
                unknown) printf '·\n' ;;
                *) printf '●\n' ;;
            esac
            ;;
        *) printf '%s\n' "$1" ;;
    esac
}

# state_token <status> <effort>: the one state token to set, as `state_<status>=<glyph>`. A status
# herdr adds later counts as `unknown`.
state_token() {
    local status=$1
    [[ " ${statuses[*]} " == *" $status "* ]] || status=unknown
    printf 'state_%s=%s\n' "$status" "$(effort_glyph "$2" "$status")"
}

# True when this process is running inside a herdr pane that can be reported on. Every caller fails
# closed on this: a Claude session started outside herdr must not make the hook noisy or slow.
in_herdr_pane() {
    [ "${HERDR_ENV:-}" = "1" ] || return 1
    [ -n "${HERDR_PANE_ID:-}" ] || return 1
    [ -n "${HERDR_SOCKET_PATH:-}" ] || return 1
    command -v "$herdr" >/dev/null 2>&1 || return 1
    return 0
}

# publish <pane> [field=<value>]...: report the given fields in one call. A field left out is left as
# it is, and one given empty is cleared. The fields:
#   mode=<mode>               $mode and $mode_label
#   model=<model>             $model
#   effort=<effort>           $effort, the level as the agent names it
#   state=<state_token>       that one $state_* token (see state_token), the other four cleared;
#                             only under $state_source_id
#
# One call rather than one per field, because herdr keeps a single sequence number per source and
# drops a report older than it whole — a model sent on its own could be lost to a mode report that
# overtook it. The two shapes of the mode share the call for a plainer reason: a row showing the bar
# of one mode beside the word of another would be worse than showing nothing.
publish() { publish_as "$source_id" "$@"; }
publish_as() {
    local source=$1 pane=$2 field value t args=()
    shift 2
    for field; do
        value=${field#*=}
        case "$field" in
            mode=?*) args+=(--token "$glyph_token=$(mode_glyph "$value")"
                --token "$label_token=$(mode_label "$value")") ;;
            mode=) args+=(--clear-token "$glyph_token" --clear-token "$label_token") ;;
            model=?*) args+=(--token "$model_token=$(model_label "$value")") ;;
            model=) args+=(--clear-token "$model_token") ;;
            effort=?*) args+=(--token "$effort_token=$value") ;;
            effort=) args+=(--clear-token "$effort_token") ;;
            state=*)
                for t in "${state_tokens[@]}"; do
                    if [ "$t" = "${value%%=*}" ]; then args+=(--token "$value"); else args+=(--clear-token "$t"); fi
                done
                ;;
        esac
    done
    [ ${#args[@]} -gt 0 ] || return 0
    "$herdr" pane report-metadata "$pane" --source "$source" --seq "$(now_ms)" "${args[@]}" >/dev/null 2>&1
}

# Every token publish can set, and the call that clears them all — each under the source that owns
# it. A field added to publish goes in both, and bin/clear and SessionEnd follow.
# shellcheck disable=SC2034  # bin/clear uses it.
all_tokens=("$glyph_token" "$label_token" "$model_token" "$effort_token" "${state_tokens[@]}")
clear_pane() {
    publish "$1" mode= model= effort=
    publish_as "$state_source_id" "$1" state=
}

# restate <pane>: have bin/state redraw the pane's glyph, in the background and a moment later. Called
# by a reporter that has just written a new $effort, which no herdr event follows. The delay lets a
# status change herdr is making from the same agent event land first; bin/state reads both values
# fresh and writes only if they differ from what is drawn.
restate() { { sleep 0.3; "${0%/*}/state" "$1"; } </dev/null >/dev/null 2>&1 & }

# Actions report back as a herdr notification, the way the sibling plugins do: an action invoked
# from a key or the UI is otherwise silent, and its failures would only ever reach `herdr plugin
# log`. bin/report never calls this — a notification per tool call would be a siren.
notify() {
    "$herdr" notification show --title "$1" --body "$2" >/dev/null 2>&1 || true
}
