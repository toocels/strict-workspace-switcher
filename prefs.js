// SPDX-License-Identifier: GPL-3.0-or-later
//
// Preferences for Strict Workspace Switcher.
//
// The extension has no settings of its own: it tightens two settings GNOME
// already has. The only one of them that GNOME Settings exposes is the
// application switcher one, so the window switcher switch here is genuinely
// useful — Alt+Tab obeys it and Settings has no UI for it.

import Adw from 'gi://Adw';
import Gio from 'gi://Gio';

import {ExtensionPreferences} from 'resource:///org/gnome/Shell/Extensions/js/extensions/prefs.js';

export default class StrictWorkspaceSwitcherPreferences extends ExtensionPreferences {
    fillPreferencesWindow(window) {
        const windowSwitcher = new Gio.Settings({schema_id: 'org.gnome.shell.window-switcher'});
        const appSwitcher = new Gio.Settings({schema_id: 'org.gnome.shell.app-switcher'});

        // Keep the Gio.Settings objects alive as long as the window is.
        window._switcherSettings = [windowSwitcher, appSwitcher];

        const page = new Adw.PreferencesPage({
            title: 'Strict mode',
            icon_name: 'preferences-system-windows-symbolic',
        });
        window.add(page);

        const switchers = new Adw.PreferencesGroup({
            title: 'Isolate the switchers to the current workspace',
            description: 'These are GNOME\'s own switcher settings. While a ' +
                'switch is on, the extension makes the matching switcher strictly ' +
                'workspace-local: a window on another workspace is never listed, ' +
                'not even when it demands attention.',
        });
        page.add(switchers);

        const windowRow = new Adw.SwitchRow({
            title: 'Window switcher (Alt+Tab)',
            subtitle: 'Switch windows / Cycle windows. GNOME Settings has no UI for ' +
                'this key, Alt+Tab obeys it anyway.',
        });
        windowSwitcher.bind('current-workspace-only', windowRow, 'active',
            Gio.SettingsBindFlags.DEFAULT);
        switchers.add(windowRow);

        const appRow = new Adw.SwitchRow({
            title: 'Application switcher (Super+Tab)',
            subtitle: 'Switch applications. Also available in Settings → Multitasking.',
        });
        appSwitcher.bind('current-workspace-only', appRow, 'active',
            Gio.SettingsBindFlags.DEFAULT);
        switchers.add(appRow);

        const behaviour = new Adw.PreferencesGroup({title: 'What changes'});
        page.add(behaviour);

        behaviour.add(new Adw.ActionRow({
            title: 'Switch off',
            subtitle: 'That switcher lists windows from every workspace, exactly as ' +
                'stock GNOME does. The extension does nothing for it.',
        }));

        behaviour.add(new Adw.ActionRow({
            title: 'Switch on',
            subtitle: 'Only windows on the current workspace are listed. A window ' +
                'that demands attention elsewhere stays out of the list; it still ' +
                'raises the usual “window is ready” notification.',
        }));

        behaviour.add(new Adw.ActionRow({
            title: 'Sticky windows are kept',
            subtitle: 'Windows shown on all workspaces (e.g. panels, always-on-top ' +
                'dashboards) are on your workspace too, so they stay listed.',
        }));
    }
}
