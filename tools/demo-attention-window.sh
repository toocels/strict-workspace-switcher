#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
#
# demo-attention-window.sh — put a window on another workspace and make it
# demand attention, so you can watch what the "current workspace only" switcher
# does with it (and prove the difference this extension makes).
#
# X11 / XWayland only: it drives the window through EWMH (_NET_WM_DESKTOP and
# _NET_WM_STATE_DEMANDS_ATTENTION), which mutter only exposes for X11 windows.
# For a Wayland-native window use the Looking Glass snippet from the README.
#
# Requirements: xdotool, xprop (x11-utils)

set -euo pipefail

usage() {
    cat <<'EOF'
Usage: demo-attention-window.sh [OPTION] [WINDOW]

Move WINDOW to another workspace and make it demand attention.

WINDOW is an X11 window id (0x…) or a title substring. If omitted, the first
Nautilus window is used.

Options:
  --clear   Undo: drop the demands-attention flag and bring the window back to
            the workspace you are on now.
  -h, --help

Examples:
  tools/demo-attention-window.sh                 # first Nautilus window
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

# --- find the target window -------------------------------------------------

if [ -n "$spec" ]; then
    case "$spec" in
        0x*) wid="$spec" ;;
        *) wid="$(xdotool search --name "$spec" 2>/dev/null | head -n1 || true)" ;;
    esac
else
    wid="$(xdotool search --class nautilus 2>/dev/null | head -n1 || true)"
fi

[ -n "$wid" ] || die "no window found${spec:+ for '$spec'} (pass a window id or a title substring)"
wid_dec=$((wid))
xprop -id "$wid_dec" _NET_WM_DESKTOP >/dev/null 2>&1 || die "window $wid does not exist"

title="$(xdotool getwindowname "$wid_dec" 2>/dev/null || echo '?')"

# --- current workspace ------------------------------------------------------

cur="$(xprop -root _NET_CURRENT_DESKTOP | grep -o '[0-9]\+$')"
ndesks="$(xprop -root _NET_NUMBER_OF_DESKTOPS | grep -o '[0-9]\+$')"

# --- clear mode -------------------------------------------------------------

if [ "$clear_flag" -eq 1 ]; then
    xdotool windowstate --remove demands_attention "$wid_dec" || true
    xdotool set_desktop_for_window "$wid_dec" "$cur" || true
    echo "cleared: \"$title\" no longer demands attention and is on workspace $((cur + 1))"
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
    [ "$id_dec" -eq "$wid_dec" ] && continue
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

xdotool set_desktop_for_window "$wid_dec" "$other" || die "could not move the window"
sleep 0.3
xdotool windowstate --add demands_attention "$wid_dec" || die "could not set the flag"
sleep 0.5

state="$(xprop -id "$wid_dec" _NET_WM_STATE 2>/dev/null || true)"

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
