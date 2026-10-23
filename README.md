# Strict Workspace Switcher

**Alt+Tab that respects your workspaces — for real.**

![GNOME Shell](https://img.shields.io/badge/GNOME%20Shell-45%E2%80%9351-blue)
![License](https://img.shields.io/badge/license-GPL--3.0--or--later-green)

GNOME Shell 45–51 · Wayland · no settings, no configuration, no dependencies ·
GPL-3.0-or-later

---

## What happens

You keep one workspace per task, so you set your switcher to *current workspace
only*. Then:

- a chat app, mail client, download manager, Steam, a CI job or an IDE build on
  **another** workspace decides it wants your attention…
- …and it appears in **this** workspace's Alt+Tab, usually as the **first**
  entry;
- you press Enter and GNOME throws you onto that other workspace, mid-task.

It happens again every time that app pings you, and GNOME has **no setting to
stop it**. The “*window title* is ready” notification is not the annoying part —
the switcher entry is.

## What this extension does

One thing: when a switcher is in *current workspace only* mode, **only windows
on the current workspace are listed** — no exception for windows that demand
attention elsewhere.

| Switcher setting | Stock GNOME | With this extension |
|---|---|---|
| current workspace only — window switcher (Alt+Tab) | current workspace **+ attention windows from every other workspace** | current workspace only |
| current workspace only — application switcher (Super+Tab) | same leak | current workspace only |
| all workspaces | every window, everywhere | unchanged |
| sticky windows (on all workspaces) | listed | still listed |

There is nothing to configure: **install it, enable it, done.** It has no
preferences, no settings key of its own and no runtime state. Disable it and
GNOME behaves exactly as before.

You keep the notification. You lose the hijacked Alt+Tab.

---

## Install

```bash
git clone https://github.com/toocels/strict-workspace-switcher
cd strict-workspace-switcher
./install.sh
```

Then reload GNOME Shell: **log out and back in.** GNOME only scans the
extensions folder at startup, so a brand new extension cannot be picked up
without one restart. (If the shell already knows the extension, `install.sh`
enables it right away and only a *code* change needs that restart — GNOME caches
extension code for the lifetime of the session.)

Then enable it — it is one line, and it is the only thing you ever have to do:

```bash
gnome-extensions enable strict-workspace-switcher@toocels
```

From [extensions.gnome.org](https://extensions.gnome.org) it is a single click
instead. From a zip:

```bash
make pack
gnome-extensions install --force dist/strict-workspace-switcher@toocels.shell-extension.zip
# log out / back in, then enable as above
```

## The one thing that has to be on

The extension only removes an *exception*. It cannot make a switcher
workspace-local that you left in *all workspaces* mode — there, listing windows
from everywhere is the whole point, so there is nothing to be strict about.

Turn on whichever switcher you actually use:

```bash
# Window switcher — what Alt+Tab is bound to on Ubuntu, Mint, Pop!_OS and any
# system where "Switch applications" was rebound. GNOME Settings has no UI for
# this key; Alt+Tab obeys it anyway.
gsettings set org.gnome.shell.window-switcher current-workspace-only true

# Application switcher — Super+Tab by default, also in
# Settings -> Multitasking -> App Switching.
gsettings set org.gnome.shell.app-switcher current-workspace-only true
```

Not sure which one your Alt+Tab uses? Whichever of these lists `<Alt>Tab`:

```bash
gsettings get org.gnome.desktop.wm.keybindings switch-windows
gsettings get org.gnome.desktop.wm.keybindings switch-applications
```

---

## Verify it works

No process outside the shell can set the attention flag on a Wayland window — the
compositor owns it — so the script below asks GNOME Shell itself to do it: open a
window on another workspace, flag it, and say what happened.

### With the script

```bash
tools/demo-attention-window.sh
```

That is all of it: the script opens a window, moves it to your other workspace,
and makes it demand attention. Nothing to pass and nothing to clean up by hand —
going to that window clears the flag again on its own.

The first run asks for one thing: GNOME Shell only runs code from outside against
its windows while its own *unsafe mode* is on. Press `Alt+F2`, type `lg`,
`Enter`, flip the **unsafe-mode** switch in the Evaluator tab, and close Looking
Glass. It lasts for the rest of the login, and the shell shows a *“System was put
in unsafe mode”* notification while it is on, with an Undo action. The script
waits for the switch and then does the rest.

There are a few optional flags, for when you want them: `--stock` and `--strict`
disable and re-enable the extension, so you can watch the same window appear in
Alt+Tab and then not; `--clear` drops the flag and moves the window back without
switching to it; `--app CMD` uses another app for the demo window; `--snippet`
prints the Looking Glass version instead of running it; `--help` lists them all.

### Then press Alt+Tab, without leaving your workspace

Run the script once as it is, then again with the extension disabled, and press
Alt+Tab each time:

```bash
tools/demo-attention-window.sh                               # extension enabled
gnome-extensions disable strict-workspace-switcher@toocels
tools/demo-attention-window.sh                               # extension disabled
gnome-extensions enable  strict-workspace-switcher@toocels   # strict again
```

- With the extension **enabled**: the window is not in the list.
- With the extension **disabled**: it is in the list, first — the stock behaviour.

Enable/disable is instant, so you can A/B it live. Going to the window clears the
flag again, or `tools/demo-attention-window.sh --clear`.

---

## What it does not do

- It does not touch the demands-attention flag, so the “*window title* is ready”
  notification still appears while you are looking elsewhere.
- It does not change focus stealing prevention.
- It does not touch the Overview, the dash, the workspace switcher or the
  animations.
- It never *loosens* anything: a switcher set to *all workspaces* behaves exactly
  as stock GNOME.

---

## Background: why it happens

You do not need any of this to use the extension — it is here because “why on
earth does it do that?” deserves an answer, and because it shows why no plain
setting can fix it.

Both switchers build their list from mutter's tab list (`js/ui/altTab.js`):

```js
function getWindows(workspace) {
    const windows = global.display.get_tab_list(Meta.TabList.NORMAL_ALL, workspace);
    ...
}
```

`workspace` is the active workspace in *current workspace only* mode and `null`
in *all workspaces* mode. mutter's `meta_display_get_tab_list()`
(`src/core/display.c`) then does this, unconditionally:

```c
  /* If filtering by workspace, include windows from
   * other workspaces that demand attention
   */
  if (workspace)
    for (w = windows; w; w = w->next)
      {
        MetaWindow *l_window = w->data;

        if (l_window->wm_state_demands_attention &&
            !meta_window_located_on_workspace (l_window, workspace) &&
            in_tab_chain (l_window, type))
          tab_list = g_list_prepend (tab_list, l_window);
      }
```

So *current workspace only* really means **“current workspace + every window
anywhere that wants attention”**. The gschema promise (“only windows from the
current workspace are shown in the switcher”) does not mention the carve-out,
and there is no key to disable it. The behaviour dates back to metacity (2009)
and upstream considers it intentional — see
[Why isn't this fixed upstream?](#why-isnt-this-fixed-upstream).

## How it works

`Meta.Display.get_tab_list()` is the single place GNOME Shell asks mutter for a
switcher list, so the extension replaces it with a wrapper:

```js
return function get_tab_list(type, workspace) {
    const windows = original.call(this, type, workspace);

    if (!workspace)              // "all workspaces" mode: leave stock behaviour
        return windows;

    return windows.filter(window => window.located_on_workspace(workspace));
};
```

`meta_window_located_on_workspace()` is exactly the predicate mutter's injection
test negates:

```c
return (window->on_all_workspaces) || (window->workspace == workspace);
```

so the filter is the precise complement of the carve-out: it removes the
injected attention windows and nothing else. (The rest of a workspace-filtered
list is the active workspace's own MRU list, whose windows are by definition
located on it; sticky windows pass the test either way.)

Patching at that level, rather than per popup, means:

- *Switch windows* (Alt+Tab), *Switch applications* (Super+Tab) and *Cycle
  windows* are all correct.
- `Ctrl+Alt+Tab` (the accessibility switcher) uses the same call and becomes
  consistent too.
- Third-party switchers built on
  `global.display.get_tab_list(type, workspace)` inherit the fix; switchers that
  build their own list are unaffected.
- The wrapper chains: if another extension has wrapped `get_tab_list`, this one
  wraps *that*, and on `disable()` it only restores its own wrapper if it is
  still the installed one, so enable/disable order cannot clobber anyone.

---

## Compatibility

- GNOME Shell **45–51** on **Wayland**.
- Developed and tested on **GNOME Shell 51.1** (Arch Linux, Wayland).

## Troubleshooting

**“I enabled it, but nothing changed.”** Check it is loaded (a freshly installed
extension needs one log out/in), and that the matching switcher setting above is
on:

```bash
gnome-extensions info strict-workspace-switcher@toocels
gnome-extensions list --enabled | grep strict-workspace-switcher
```

**“The window still shows up.”** mutter clears the attention flag the moment the
window is focused, so verify with a window you are *not* focused on.

**“A sticky window shows up.”** Windows on all workspaces (panels,
always-on-top dashboards) are on your workspace too, so they are kept.

**Logs:** `journalctl --user -f -o cat | grep strict-workspace-switcher`

## Uninstall

```bash
./uninstall.sh          # or: make uninstall
                        # or: gnome-extensions uninstall strict-workspace-switcher@toocels
```

Your GNOME switcher settings are left exactly as they were — they belong to you,
not to the extension.

---

## FAQ

### Why isn't this fixed upstream?

Because the behaviour is deliberate: apps that ask for attention are supposed to
surface. Even in the closely related MATE/`marco` tracker, where users filed the
same complaint, the maintainer's answer was *“This behaviour is intentional …
This is by design”* — the offered fix was an option to change the **ordering** of
urgent windows, not to exclude them
([marco#824](https://github.com/mate-desktop/marco/issues/824)).

The mechanism is documented in mutter's own history: the 2019 commit `d2ca5cc2`
(“display: Fix inconsistent behavior with demand attention”,
[issue #523](https://gitlab.gnome.org/GNOME/mutter/-/issues/523)) explicitly
describes “a mechanism in `meta_display_get_tab_list()` which forces the windows
with the demand attention flag set to be placed first in the MRU list when
they're placed on a workspace different from the current one”.

So this extension is the pragmatic route: keep the notification, drop the
switcher entry, no compositor rebuild.

### Doesn't “current workspace only” already mean this?

It means “current workspace, plus anything that demands attention anywhere”. The
tab list is workspace-filtered first and the attention windows are prepended
afterwards, as shown [above](#background-why-it-happens).

### I want the attention window kept, but not moved to the front. Can this do that?

No — this extension removes the entry, it does not reorder it. Reordering would
mean re-implementing the switcher list order instead of filtering it.

### Can I do this without an extension?

Only by patching mutter: delete the `if (workspace) …` block in
`meta_display_get_tab_list()` (`src/core/display.c`) and rebuild. That is a fork
of your compositor; this extension is the same behaviour, revertible at runtime.

### Does it work with other switcher extensions?

If they ask GNOME Shell for the tab list (`get_tab_list(type, workspace)`), they
inherit the fix. If they build their own window list, they are unaffected.

### Related reading

- [r/gnome — “Strange behavior on AltTab after notification from app in different workspace”](https://www.reddit.com/r/gnome/comments/vh9t39/strange_behavior_on_alttab_after_notification/)
- [linuxmint/muffin#646 — “No way to prevent focus stealing”](https://github.com/linuxmint/muffin/issues/646)
- [GNOME Discourse — Understanding GNOME Shell's focus stealing prevention](https://discourse.gnome.org/t/understanding-gnome-shell-s-focus-stealing-prevention/23434)

---

## License

GNU General Public License v3.0 or later — see [LICENSE](LICENSE).

This program is free software: you can redistribute it and/or modify it under
the terms of the GNU General Public License as published by the Free Software
Foundation, either version 3 of the License, or (at your option) any later
version.

Source references are from GNOME Shell 51.1 / mutter 51 and are quoted for
explanation only; mutter and GNOME Shell are licensed under GPL-2.0-or-later.
