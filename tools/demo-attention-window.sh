#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
#
# demo-attention-window.sh — open a window on another workspace, make it demand
# attention, and tell you what Alt+Tab shows.
#
# On Wayland only the compositor can move a window between workspaces or set the
# demands-attention flag, so this drives GNOME Shell through its own evaluation
# interface (the same one Looking Glass uses).  That interface is behind GNOME's
# "unsafe mode" switch, which only you can flip — see the printed instructions,
# it is one switch, once per login.
#
# Options:
#   --app CMD       open CMD instead of the default demo app
#   --stock         disable the extension, so Alt+Tab shows stock GNOME
#   --strict        re-enable the extension
#   --clear         drop the flag and move the demo window back to your workspace
#   --close         like --clear, and close the window too
#   --snippet       print the equivalent Looking Glass snippet and exit
#   --wait SECONDS  how long to wait for unsafe mode to be switched on (default 300)
#   -h, --help

set -euo pipefail

UUID="strict-workspace-switcher@toocels"
SHELL_BUS="org.gnome.Shell"
SHELL_PATH="/org/gnome/Shell"
SHELL_IFACE="org.gnome.Shell"

# Default demo apps, in order of preference: small, harmless, and a window of
# their own rather than a second tab in something you are working in.
DEFAULT_APPS="gnome-calculator gnome-text-editor gnome-clocks nautilus"

# app command -> Wayland app id, so we can also find a window the app already
# had open (these apps are single-instance and may just reuse it).
app_id_for() {
    case "$1" in
        *gnome-calculator*)   echo "org.gnome.Calculator" ;;
        *gnome-text-editor*)  echo "org.gnome.TextEditor" ;;
        *gnome-clocks*)       echo "org.gnome.clocks" ;;
        *nautilus*)           echo "org.gnome.Nautilus" ;;
        *)                    echo "" ;;
    esac
}

die() { echo "error: $*" >&2; exit 1; }

# --- options ----------------------------------------------------------------

mode="demo"
app=""
wait_seconds=300
close_too=0

while [ $# -gt 0 ]; do
    case "$1" in
        --app)     app="${2:-}"; [ -n "$app" ] || die "--app needs a command"; shift ;;
        --stock)   mode="stock" ;;
        --strict)  mode="strict" ;;
        --clear)   mode="clear" ;;
        --close)   mode="clear"; close_too=1 ;;
        --snippet) mode="snippet" ;;
        --wait)    wait_seconds="${2:-}"; [ -n "$wait_seconds" ] || die "--wait needs a number of seconds"; shift ;;
        -h|--help) mode="help" ;;
        *)         die "unknown option: $1 (try --help)" ;;
    esac
    shift
done

case "$wait_seconds" in
    ''|*[!0-9]*) die "--wait needs a number of seconds, got: $wait_seconds" ;;
esac

use_extension() {                     # --stock / --strict, plain D-Bus calls
    case "$1" in
        stock)  gnome-extensions disable "$UUID" >/dev/null 2>&1 || true
                echo "disabled $UUID — the switcher now behaves like stock GNOME" ;;
        strict) gnome-extensions enable  "$UUID" >/dev/null 2>&1 || true
                echo "enabled $UUID — the switcher is workspace-strict again" ;;
    esac
    sleep 1
    gnome-extensions info "$UUID" 2>/dev/null | grep -E 'State:' || true
    echo
    echo "Press Alt+Tab while staying on your workspace to see the difference."
}

case "$mode" in
    help)
        sed -n '3,21p' "$0" | sed 's/^# \{0,1\}//'
        exit 0 ;;
    stock|strict)
        use_extension "$mode"
        exit 0 ;;
esac

command -v gdbus >/dev/null 2>&1 || die "gdbus not found (install glib2)"

# --- the code we make the shell run -----------------------------------------
#
# Notes for whoever edits this: the JS is handed to gdbus as one single-quoted
# GVariant string, so it must not contain single quotes, backslashes or // line
# comments (newlines are stripped before the call).

read -r -d '' JS_DEMO <<'JS' || true
(async () => {
    const GLib = imports.gi.GLib;
    const Meta = imports.gi.Meta;
    const display = global.display;
    const manager = global.workspace_manager;

    const sleep = ms => new Promise(resolve => {
        GLib.timeout_add(GLib.PRIORITY_DEFAULT, ms, () => {
            resolve();
            return GLib.SOURCE_REMOVE;
        });
    });

    /* build quotes with fromCharCode: a literal one cannot be sent to the shell */
    const quote = String.fromCharCode(39);
    const clean = s => s.split(quote).join("");

    let window = null;
    const existing = display.get_window_actors()
        .map(actor => actor.meta_window)
        .filter(win => win.get_title() && !win.is_skip_taskbar() &&
                       win.get_window_type() === Meta.WindowType.NORMAL);
    const before = new Set(existing);

    GLib.spawn_command_line_async("__APP__");

    for (let i = 0; i < 60 && !window; i++) {
        await sleep(250);
        window = display.get_window_actors()
            .map(actor => actor.meta_window)
            .find(win => !before.has(win) && win.get_title() &&
                         win.get_window_type() === Meta.WindowType.NORMAL);
    }

    if (!window && "__APP_ID__") {
        window = existing.find(win => win.get_gtk_application_id() === "__APP_ID__" &&
                                     !win.is_on_all_workspaces());
    }

    if (!window)
        return "the app did not open a window - try --app with another app";

    const active = manager.get_active_workspace();
    const other = active.index() === 0 ? 1 : 0;

    window.change_workspace_by_index(other, true);
    await sleep(300);
    window.activate(0);
    await sleep(600);

    const dq = String.fromCharCode(34);
    return "window " + dq + clean(window.get_title()) + dq + " - you are on workspace " +
           (active.index() + 1) + ", it is on workspace " + (other + 1) +
           ", demands_attention=" + window.demands_attention;
})()
JS

read -r -d '' JS_CLEAR <<'JS' || true
(async () => {
    const display = global.display;
    const active = global.workspace_manager.get_active_workspace();
    const done = [];

    display.get_window_actors().map(actor => actor.meta_window).forEach(win => {
        if (win.demands_attention && !win.located_on_workspace(active)) {
            win.unset_demands_attention();
            win.change_workspace_by_index(active.index(), true);
            done.push(win.get_title());
            if ("__CLOSE__" === "yes")
                win.delete(global.get_current_time());
        }
    });

    if (done.length === 0)
        return "nothing to undo - no window on another workspace demands attention";

    return "undone for: " + done.join(", ");
})()
JS

# --- shell evaluation -------------------------------------------------------

one_line() { tr -d '\n' <<< "$1"; }

eval_ready() {
    [ "$(gdbus call --session --dest "$SHELL_BUS" --object-path "$SHELL_PATH" \
            --method "$SHELL_IFACE.Eval" "'1'" 2>/dev/null || true)" = "(true, '1')" ]
}

shell_eval() {                        # prints the raw result string
    local out
    out="$(gdbus call --session --dest "$SHELL_BUS" --object-path "$SHELL_PATH" \
              --method "$SHELL_IFACE.Eval" "'$(one_line "$1")'" 2>&1)" ||
        die "could not talk to GNOME Shell: $out"

    case "$out" in
        "(false, '')"*)
            die "GNOME Shell refused to run the code (unsafe mode is off)" ;;
    esac

    if [ "${out:0:7}" = "(false," ]; then
        die "the shell reported an error: ${out:9:-2}"
    fi

    printf '%s\n' "${out:8:-2}"
}

need_unsafe_mode() {
    cat >&2 <<EOF
GNOME Shell only lets a process outside the shell move windows or set the
demands-attention flag when the shell's own "unsafe mode" is switched on.
That is GNOME's safety gate for running code inside the shell and nothing in a
script can bypass it.

Turn it on once per login:

  1. press Alt+F2, type  lg  and press Enter
  2. in Looking Glass, flip the unsafe-mode switch (Evaluator tab)
  3. close Looking Glass

The shell shows a "System was put in unsafe mode" notification while it is on,
and you can Undo it from there when you are done. It only lasts for this login.

Waiting up to ${wait_seconds}s for it... (Ctrl-C to give up)
EOF

    local waited=0
    while [ "$waited" -lt "$wait_seconds" ]; do
        sleep 2
        waited=$((waited + 2))
        if eval_ready; then
            echo "unsafe mode is on - continuing" >&2
            return 0
        fi
    done

    die "unsafe mode is still off"
}

# --- main -------------------------------------------------------------------

if [ "$mode" = "snippet" ]; then
    [ -n "$app" ] || for candidate in $DEFAULT_APPS; do
        command -v "$candidate" >/dev/null 2>&1 && { app="$candidate"; break; }
    done
    [ -n "$app" ] || die "no demo app found - pass --app CMD"
    snippet="${JS_DEMO//__APP__/$app}"
    snippet="${snippet//__APP_ID__/$(app_id_for "$app")}"
    echo "Paste this into Looking Glass (Alt+F2, type lg, Enter) - Evaluator tab:"
    echo
    echo "$snippet"
    exit 0
fi

eval_ready || need_unsafe_mode

case "$mode" in
    clear)
        result="$(shell_eval "${JS_CLEAR//__CLOSE__/$([ "$close_too" -eq 1 ] && echo yes || echo no)}")"
        echo "$result"
        exit 0 ;;
esac

[ -n "$app" ] || for candidate in $DEFAULT_APPS; do
    command -v "$candidate" >/dev/null 2>&1 && { app="$candidate"; break; }
done
[ -n "$app" ] || die "no demo app found - pass --app CMD"

# a quick sanity line, so a failure to reach the shell is obvious
echo "shell: $(shell_eval '"workspace " + (global.workspace_manager.get_active_workspace().index() + 1) + " of " + global.workspace_manager.n_workspaces + ", " + global.display.get_window_actors().length + " windows"' 2>/dev/null || echo "?")"
echo "opening: $app"

js="${JS_DEMO//__APP__/$app}"
js="${js//__APP_ID__/$(app_id_for "$app")}"

result="$(shell_eval "$js")"
echo "$result"

case "$result" in
    "window "*)
        echo
        echo "Now press Alt+Tab while staying on your workspace:"
        echo "  * extension enabled  -> that window is NOT in the list"
        echo "  * extension disabled -> it is the first entry (stock behaviour)"
        echo
        echo "  $0 --stock     disable the extension and look again"
        echo "  $0 --strict    enable it again"
        echo "  $0 --clear     drop the flag and bring the window back"
        ;;
esac
