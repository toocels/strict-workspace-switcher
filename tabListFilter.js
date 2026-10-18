// SPDX-License-Identifier: GPL-3.0-or-later
//
// The whole behaviour of Strict Workspace Switcher, kept free of any GNOME
// imports so it can be unit-tested outside of the shell
// (see tests/tab-list-filter.test.js).
//
// Background: when a switcher is in "current workspace only" mode, GNOME Shell
// calls global.display.get_tab_list(type, activeWorkspace) and mutter answers
// with the windows of that workspace plus — unconditionally, and with no
// setting to turn it off — every window from another workspace that has the
// demands-attention flag set (meta_display_get_tab_list(), src/core/display.c).
//
// meta_window_located_on_workspace() is exactly the predicate that injection
// test negates, so filtering on it removes the injected windows and nothing
// else.

/**
 * Wrap a Meta.Display.get_tab_list() implementation so that a workspace-filtered
 * tab list is strictly limited to that workspace.
 *
 * The wrapper is meant to be installed as a method of Meta.Display, so it
 * forwards its `this` (the display) to the original implementation.
 *
 * @param {function(number, ?object): Array<object>} original - implementation to wrap
 * @returns {function(number, ?object): Array<object>} the workspace-strict implementation
 */
export function makeWorkspaceStrict(original) {
    if (typeof original !== 'function')
        throw new TypeError('makeWorkspaceStrict: original must be a function');

    return function get_tab_list(type, workspace) {
        const windows = original.call(this, type, workspace);

        // No workspace requested: the switcher is in "all workspaces" mode and
        // stock behaviour is the desired behaviour.
        if (!workspace)
            return windows;

        return windows.filter(window => window.located_on_workspace(workspace));
    };
}
