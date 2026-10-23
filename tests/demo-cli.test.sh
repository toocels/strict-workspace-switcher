#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
#
# Tests for the bash half of tools/demo-attention-window.sh: the gdbus call, how
# the shell's answer is read back, and what the script tells you. tests/stub-bin
# has a gdbus that answers the way org.gnome.Shell.Eval does, so this runs with
# no GNOME session, no window, and no unsafe mode:
#
#     make test
#     # or: bash tests/demo-cli.test.sh

set -uo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
script="$here/../tools/demo-attention-window.sh"
stub="$here/stub-bin"

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

failures=0
out=""
status=0

pass() { echo "ok   - $1"; }
fail() { failures=$((failures + 1)); echo "FAIL - $1"; }

is() {  # is <description> <expected status> <actual status>
    if [ "$2" = "$3" ]; then
        pass "$1"
    else
        fail "$1 (expected exit status $2, got $3)"
    fi
}

has() {  # has <description> <needle>
    case "$out" in
        *"$2"*) pass "$1" ;;
        *) fail "$1 (looked for: $2)"
           printf '%s\n' "$out" | head -20 | sed 's/^/       | /' ;;
    esac
}

lacks() {  # lacks <description> <needle>
    case "$out" in
        *"$2"*) fail "$1 (did not expect to see: $2)"
                printf '%s\n' "$out" | head -20 | sed 's/^/       | /' ;;
        *) pass "$1" ;;
    esac
}

# Runs the script with the stub gdbus in front of the real one.
run() {
    local mode="$1"
    shift
    : > "$work/calls.log"
    out="$(STUB_MODE="$mode" STUB_LOG="$work/calls.log" \
           PATH="$stub:$PATH" "$script" "$@" 2>&1)"
    status=$?
}

# The code the script sent to the shell, on one line per call.
sent_code() { tr '\n' ' ' < "$work/calls.log"; }

# --- the script itself -------------------------------------------------------

if bash -n "$script" 2>"$work/parse.log"; then
    pass "script: parses as bash"
else
    fail "script: parses as bash"
    sed 's/^/       | /' "$work/parse.log"
fi

# --- the demo ----------------------------------------------------------------

run ok --app demo-app
is "demo: exits 0 when the shell runs the code" 0 "$status"
has "demo: prints what the shell reports" "shell: workspace 1 of 3, 4 windows"
has "demo: says which app it is opening" "opening: demo-app"
has "demo: prints the result unquoted and unescaped" \
    'window "Demo Document" - you are on workspace 1, it is on workspace 2, demands_attention=true'
has "demo: explains what Alt+Tab should show" "extension enabled  -> that window is NOT in the list"
has "demo: says how to undo it without switching" "--clear"
case "$(sent_code)" in
    *global.get_window_actors*) pass "demo: sends code that uses global.get_window_actors" ;;
    *) fail "demo: sends code that uses global.get_window_actors"
       printf '%s\n' "$(sent_code)" | head -20 | sed 's/^/       | /' ;;
esac

# --- --clear -----------------------------------------------------------------

run ok --clear
is "clear: exits 0" 0 "$status"
has "clear: says which window it fixed" "undone for: Flagged Window"
lacks "clear: no Alt+Tab explanation" "extension enabled  -> that window is NOT in the list"

run ok --close
is "clear --close: exits 0" 0 "$status"
has "clear --close: says which window it fixed" "undone for: Flagged Window"

# --- unsafe mode is off ------------------------------------------------------

run off --app demo-app --wait 0
is "unsafe mode off: exits 1" 1 "$status"
has "unsafe mode off: explains the switch" "Turn it on once per login"
has "unsafe mode off: names Looking Glass" "type  lg  and press Enter"
has "unsafe mode off: gives up instead of hanging" "unsafe mode is still off"
lacks "unsafe mode off: does not claim to have opened a window" "opening: demo-app"

# --- the shell refuses the code ----------------------------------------------

run error --app demo-app
is "shell error: exits 1" 1 "$status"
has "shell error: shows what the shell said" \
    "the shell reported an error: TypeError: this-broke is not a function"
lacks "shell error: does not carry on to open the app" 'window "Demo Document"'

# --- --snippet / --help / bad usage ------------------------------------------

run ok --snippet
is "snippet: exits 0" 0 "$status"
has "snippet: prints the code it would run" "spawn_command_line_async"
has "snippet: says where to paste it" "Paste this into Looking Glass"
if [ -s "$work/calls.log" ]; then
    fail "snippet: does not talk to the shell"
else
    pass "snippet: does not talk to the shell"
fi

run ok --help
is "help: exits 0" 0 "$status"
has "help: lists the options" "--wait SECONDS"

run ok --wait abc --app demo-app
is "bad --wait: exits 1" 1 "$status"
has "bad --wait: says what it wanted" "--wait needs a number of seconds"

run ok --app
is "--app without a value: exits 1" 1 "$status"
has "--app without a value: says what it wanted" "--app needs a command"

run ok --nonsense
is "unknown option: exits 1" 1 "$status"
has "unknown option: says so" "unknown option: --nonsense"

# --- summary -----------------------------------------------------------------

if [ "$failures" -gt 0 ]; then
    echo "$failures test(s) failed" >&2
    exit 1
fi

echo "all tests passed"
