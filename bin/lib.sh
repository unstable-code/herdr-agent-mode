#!/usr/bin/env bash
# Shared helpers for bin/report (the Claude hook entry point), bin/hooks and bin/clear.

herdr=${HERDR_BIN_PATH:-herdr}
source_id=unstable-code.herdr-agent-mode
glyph_token=mode
label_token=mode_label
# shellcheck disable=SC2034  # bin/hooks uses it; this file is sourced, not run.
settings_file="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/settings.json"

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
        plan) printf '▏\n' ;;              # read-only
        dontAsk) printf '▎\n' ;;           # auto-denies
        default) printf '▍\n' ;;           # manual, asks every time
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

# True when this process is running inside a herdr pane that can be reported on. Every caller fails
# closed on this: a Claude session started outside herdr must not make the hook noisy or slow.
in_herdr_pane() {
    [ "${HERDR_ENV:-}" = "1" ] || return 1
    [ -n "${HERDR_PANE_ID:-}" ] || return 1
    [ -n "${HERDR_SOCKET_PATH:-}" ] || return 1
    command -v "$herdr" >/dev/null 2>&1 || return 1
    return 0
}

# publish <pane> [mode]: report both shapes of the mode, or clear both when no mode is given.
# One call and one sequence number for the pair — they are the same fact, and a row showing the bar
# of one mode beside the word of another would be worse than showing nothing.
publish() {
    local pane=$1 mode=${2:-} seq
    seq=$(now_ms)
    if [ -n "$mode" ]; then
        "$herdr" pane report-metadata "$pane" --source "$source_id" --seq "$seq" \
            --token "$glyph_token=$(mode_glyph "$mode")" \
            --token "$label_token=$(mode_label "$mode")" >/dev/null 2>&1
    else
        "$herdr" pane report-metadata "$pane" --source "$source_id" --seq "$seq" \
            --clear-token "$glyph_token" --clear-token "$label_token" >/dev/null 2>&1
    fi
}

# Actions report back as a herdr notification, the way the sibling plugins do: an action invoked
# from a key or the UI is otherwise silent, and its failures would only ever reach `herdr plugin
# log`. bin/report never calls this — a notification per tool call would be a siren.
notify() {
    "$herdr" notification show --title "$1" --body "$2" >/dev/null 2>&1 || true
}
