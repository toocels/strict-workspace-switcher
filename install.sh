#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
#
# install.sh — install Strict Workspace Switcher for the current user.
#
# No make, no root, no dependencies: copies the extension into the GNOME Shell
# extensions directory and enables it if the running shell already knows it.

set -euo pipefail

UUID="strict-workspace-switcher@toocels"
SOURCES="metadata.json extension.js tabListFilter.js"

cd "$(dirname "$0")"

TARGET="${XDG_DATA_HOME:-$HOME/.local/share}/gnome-shell/extensions/$UUID"

for file in $SOURCES; do
    [ -f "$file" ] || {
        echo "error: $file not found — run this from the extension source tree" >&2
        exit 1
    }
done

grep -q "\"$UUID\"" metadata.json || {
    echo "error: metadata.json does not declare $UUID" >&2
    exit 1
}

rm -rf "$TARGET"
mkdir -p "$TARGET"
# shellcheck disable=SC2086
cp $SOURCES "$TARGET/"

echo "installed: $TARGET"

if gnome-extensions list 2>/dev/null | grep -qx "$UUID"; then
    # The shell knows this extension from a previous start, so it can be
    # enabled (or re-enabled) right away.
    gnome-extensions enable "$UUID" >/dev/null 2>&1 || true
    cat <<EOF

The running GNOME Shell already knows this extension and it is enabled.

Note: GNOME caches extension code for the lifetime of the session, so if you
reinstalled over an older copy, the new files only take effect after a shell
restart (Wayland: log out and back in; X11: Alt+F2, type "r", Enter).
EOF
else
    cat <<EOF

GNOME Shell only scans the extensions directory at startup, so a newly
installed extension needs one shell restart:

  * Wayland: log out and back in
  * X11:     press Alt+F2, type "r", press Enter

Then enable it:

  gnome-extensions enable $UUID
EOF
fi

echo
echo "Uninstall with ./uninstall.sh"
