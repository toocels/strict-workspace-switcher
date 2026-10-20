#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
#
# demo-attention-window.sh — put a window on another workspace and make it
# demand attention, so you can watch what the "current workspace only" switcher
# does with it (and prove the difference this extension makes).
#
# X11 / XWayland only: it drives the window through EWMH (_NET_WM_DESKTOP and
# _NET_WM_STATE_DEMANDS_ATTENTION), which mutter only exposes for X11 windows.
# A Wayland-native window cannot be driven from outside the compositor — for
# one of those use the Looking Glass snippet from the README.
#
# Which window does it use? The WINDOW you name, else the first X11 window it
# can find (a window titled "attention-demo", then Nautilus, then glxgears).
# If it finds none it starts its own demo window, so this works even on a
# session where every app you have open is Wayland-native. Note that
# "GDK_BACKEND=x11 nautilus" does NOT give you an X11 window when Nautilus is
# already running — the new process just hands the request to the running
# Wayland instance.
#
# Requirements: xdotool, xprop (x11-utils); glxgears (mesa-utils) only when a
# demo window has to be started.

set -euo pipefail

DEMO_TITLE="attention-demo"

usage() {
    cat <<'EOF'
Usage: demo-attention-window.sh [OPTION] [WINDOW]

Move WINDOW to another workspace and make it demand attention.

WINDOW is an X11 window id (0x…) or a title/class substring. If omitted, the
first usable X11 window is used (a window titled "attention-demo", else
Nautilus, else glxgears) and, if there is none, a demo window is started.

Options:
  --clear   Undo: drop the demands-attention flag and bring the window back to
            the workspace you are on now.
  -h, --help

Examples:
  tools/demo-attention-window.sh                 # find or start a demo window
  tools/demo-attention-window.sh "attention-demo"
  tools/demo-attention-window.sh 0x1800004
  tools/demo-attention-window.sh --clear "attention-demo"
EOF
}

die() {
    echo "error: $*" >&2
    exit 1
}

for tool in xdotool xprop; do
    command -v "$tool" >/dev/null 2>&1 || die "$tool not found (install xdotool / x11-utils)"
done

clear_flag=0
spec=""
while [ $# -gt 0 ]; do
    case "$1" in
        --clear) clear_flag=1 ;;
        -h|--help) usage; exit 0 ;;
        -*) die "unknown option: $1" ;;
        *) spec="$1" ;;
    esac
    shift
done

# --- window lookup ----------------------------------------------------------

no_window_hint() {
    cat >&2 <<'EOF'
       No X11 window matched. Windows of Wayland-native apps cannot be driven
       from here, and "GDK_BACKEND=x11 <app>" only works if that app is not
       already running (otherwise the request goes to the running Wayland
       instance). Either name an X11/XWayland window, or run this without a
       WINDOW argument so it starts its own demo window. For a Wayland-native
       window, use the Looking Glass snippet from the README.
EOF
}

# Prints a decimal window id (or nothing).
lookup() {
    local spec="$1" id=""

    if [ -n "$spec" ]; then
        case "$spec" in
            0x*|0X*) printf '%d' "$spec"; return 0 ;;
        esac
        id="$(xdotool search --name  "$spec" 2>/dev/null | head -n1 || true)"
        [ -n "$id" ] || id="$(xdotool search --class "$spec" 2>/dev/null | head -n1 || true)"
    else
        for candidate in "$DEMO_TITLE" nautilus glxgears; do
            id="$(xdotool search --name  "$candidate" 2>/dev/null | head -n1 || true)"
            [ -n "$id" ] || id="$(xdotool search --class "$candidate" 2>/dev/null | head -n1 || true)"
            [ -n "$id" ] && break
        done
    fi

    printf '%s' "$id"
}

# Wait for `lookup WINDOW` to find something, up to ~5 seconds: the caller may
# have started the window a moment ago.
lookup_wait() {
    local spec="$1" id
    for _ in $(seq 1 20); do
        id="$(lookup "$spec")"
        [ -n "$id" ] && { printf '%s' "$id"; return 0; }
        sleep 0.25
    done
    return 0
}

wid="$(lookup_wait "$spec")"

# Nothing usable and nothing to undo: make our own demo window.
if [ -z "$wid" ] && [ "$clear_flag" -eq 0 ]; then
    command -v glxgears >/dev/null 2>&1 || {
        echo "error: no X11 window found to use, and glxgears is not installed" >&2
        echo "       (install mesa-utils, or name an X11 window)." >&2
        no_window_hint
        exit 1
    }

    echo "no usable X11 window found — starting one (glxgears)"
    glxgears >/dev/null 2>&1 &
    wid="$(lookup_wait glxgears)"
    [ -n "$wid" ] || die "glxgears did not open a window"
    xdotool set_window --name "$DEMO_TITLE" "$wid" 2>/dev/null || true
    launched=1
else
    launched=0
fi

if [ -z "$wid" ]; then
    echo "error: no window found${spec:+ for '$spec'}" >&2
    no_window_hint
    exit 1
fi

xprop -id "$wid" _NET_WM_DESKTOP >/dev/null 2>&1 || die "window $wid does not exist"

title="$(xdotool getwindowname "$wid" 2>/dev/null || echo '?')"
title="${title:-?}"

# --- current workspace ------------------------------------------------------
#
# mutter only writes _NET_CURRENT_DESKTOP when the active workspace changes, so
# on a fresh session (or any session where you have not switched workspaces
# yet) the property is simply not there. Fall back to the desktop of the
# focused window, and last to the target's own desktop.

desktop_of() {
    xprop -id "$1" _NET_WM_DESKTOP 2>/dev/null | grep -o '[0-9]\+$' | head -n1
}

ndesks="$(xprop -root _NET_NUMBER_OF_DESKTOPS | grep -o '[0-9]\+$' | head -n1)"

assumed=""
cur="$(xdotool get_desktop 2>/dev/null || true)"
case "$cur" in ''|*[!0-9]*) cur="" ;; esac

if [ -z "$cur" ]; then
    active="$(xprop -root _NET_ACTIVE_WINDOW 2>/dev/null | grep -o '0x[0-9a-f]*' | head -n1)"
    [ -n "$active" ] && cur="$(desktop_of "$((active))")"
fi

if [ -z "$cur" ]; then
    cur="$(desktop_of "$wid")"
    assumed=1
fi

# --- clear mode -------------------------------------------------------------

if [ "$clear_flag" -eq 1 ]; then
    xdotool windowstate --remove demands_attention "$wid" || true
    xdotool set_desktop_for_window "$wid" "$cur" || true
    echo "cleared: \"$title\" no longer demands attention and is on workspace $((cur + 1))"
    if xprop -id "$wid" WM_CLASS 2>/dev/null | grep -qi glxgears; then
        echo "close the demo window with: pkill glxgears"
    fi
    exit 0
fi

# --- move + flag ------------------------------------------------------------

[ "$ndesks" -ge 2 ] || die "need at least 2 workspaces (found $ndesks)"

if [ "$cur" -eq 0 ]; then other=1; else other=0; fi

# If the target is the focused window, mutter may re-focus it after the move and
# clear the flag again (meta_window_focus() unsets demands-attention). Focusing
# something else on this workspace first makes the flag stick.
other_win=""
for id in $(xprop -root _NET_CLIENT_LIST | grep -o '0x[0-9a-f]*'); do
    id_dec=$((id))
    [ "$id_dec" -eq "$wid" ] && continue
    dsk="$(xprop -id "$id_dec" _NET_WM_DESKTOP 2>/dev/null | grep -o '[0-9]\+$' || echo -1)"
    if [ "$dsk" = "$cur" ]; then
        other_win="$id_dec"
        break
    fi
done

if [ -n "$other_win" ]; then
    xdotool windowactivate "$other_win" >/dev/null 2>&1 || true
    sleep 0.2
else
    echo "note: no other window on workspace $((cur + 1)); if the flag does not stick,"
    echo "      click any window on your workspace and run this again."
fi

xdotool set_desktop_for_window "$wid" "$other" || die "could not move the window"
sleep 0.3
xdotool windowstate --add demands_attention "$wid" || die "could not set the flag"
sleep 0.5

state="$(xprop -id "$wid" _NET_WM_STATE 2>/dev/null || true)"

if [ -n "$assumed" ]; then
    cat <<EOF
note: mutter has not published _NET_CURRENT_DESKTOP in this session yet (it only
      does so once you switch workspaces), so "you are" below is assumed from
      the window you pointed at. If it is wrong, switch workspaces once and
      re-run.
EOF
fi

cat <<EOF
window:   "$title" (id $wid)
you are: workspace $((cur + 1))
it is:   workspace $((other + 1))
state:   $state
EOF

if ! printf '%s' "$state" | grep -q _NET_WM_STATE_DEMANDS_ATTENTION; then
    cat >&2 <<'EOF'

warning: the flag is not set any more. The usual cause is that the window was
         (or became) the focused window, and mutter clears demands-attention as
         soon as a window is focused. Focus something else, then re-run.
EOF
    exit 1
fi

cat <<EOF

Now press Alt+Tab while staying on workspace $((cur + 1)).
  * extension enabled  -> "$title" is NOT in the list
  * extension disabled -> "$title" is the first entry (stock mutter behaviour)

Toggle the extension without logging out once it is installed:
  gnome-extensions disable strict-workspace-switcher@toocels
  gnome-extensions enable  strict-workspace-switcher@toocels

Clean up:
  $(basename "$0") --clear "$title"
EOF
