// SPDX-License-Identifier: GPL-3.0-or-later
//
// Strict Workspace Switcher — a GNOME Shell extension.
//
// THE PROBLEM
//
// When a switcher is in "current workspace only" mode, GNOME Shell asks mutter
// for a workspace filtered tab list:
//
//     global.display.get_tab_list(Meta.TabList.NORMAL_ALL, activeWorkspace);
//     // js/ui/altTab.js, getWindows()
//
// mutter answers with the windows of that workspace — and then prepends every
// window from *any other* workspace whose demands-attention flag is set
// (meta_display_get_tab_list(), src/core/display.c):
//
//     if (workspace)
//       for (w = windows; w; w = w->next)
//         {
//           MetaWindow *l_window = w->data;
//           if (l_window->wm_state_demands_attention &&
//               !meta_window_located_on_workspace (l_window, workspace) &&
//               in_tab_chain (l_window, type))
//             tab_list = g_list_prepend (tab_list, l_window);
//         }
//
// There is no setting that disables this, so a chat client, mail client or
// download that wants attention on another workspace ends up (usually first)
// in your Alt+Tab, even though you asked for "current workspace only".
//
// WHAT THIS DOES
//
// It wraps get_tab_list() and drops every window that is not located on the
// workspace that was asked for. `meta_window_located_on_workspace()` is exactly
// the predicate mutter's injection test negates, so this removes precisely the
// injected windows and nothing else:
//
//   * switcher in "current workspace only" mode -> strict, no exceptions
//   * switcher in "all workspaces" mode         -> untouched (workspace == null)
//   * windows that are on all workspaces (sticky) -> kept, they are on every
//     workspace and therefore not "another workspace"
//
// Everything else is left alone: the demands-attention flag itself, the
// "… is ready" notification, focus stealing prevention, the Overview, the dash.

import Meta from 'gi://Meta';

import {Extension} from 'resource:///org/gnome/shell/extensions/extension.js';

import {makeWorkspaceStrict} from './tabListFilter.js';

const LOG_TAG = 'strict-workspace-switcher';

export default class StrictWorkspaceSwitcherExtension extends Extension {
    enable() {
        const proto = Meta.Display.prototype;

        // Guard against enable() without a matching disable().
        if (this._strict && proto.get_tab_list === this._strict)
            return;

        this._original = proto.get_tab_list;
        this._strict = makeWorkspaceStrict(this._original);

        proto.get_tab_list = this._strict;

        console.debug(`${LOG_TAG}: switcher tab list is now workspace-strict`);
    }

    disable() {
        const proto = Meta.Display.prototype;

        // Only put back what we installed, so we don't clobber another
        // extension that wrapped get_tab_list after us.
        if (this._original && proto.get_tab_list === this._strict)
            proto.get_tab_list = this._original;

        this._original = null;
        this._strict = null;

        console.debug(`${LOG_TAG}: switcher tab list restored`);
    }
}
