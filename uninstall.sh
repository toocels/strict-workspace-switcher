#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
#
# uninstall.sh — remove Strict Workspace Switcher for the current user.
#
# Disables the extension (which also drops it from the enabled-extensions
# setting) and deletes the installed files. Your GNOME switcher settings are
# left exactly as they are — they belong to you, not to this extension.

set -euo pipefail

UUID="strict-workspace-switcher@toocels"

TARGET="${XDG_DATA_HOME:-$HOME/.local/share}/gnome-shell/extensions/$UUID"

gnome-extensions disable "$UUID" >/dev/null 2>&1 || true

if [ -d "$TARGET" ]; then
    rm -rf "$TARGET"
    echo "removed: $TARGET"
else
    echo "not installed: $TARGET"
fi

cat <<EOF

If the extension was active in your current session it is now disabled. The
directory is gone, so it cannot come back at your next login.
EOF
