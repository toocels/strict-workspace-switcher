# Strict Workspace Switcher

**Alt+Tab that respects your workspaces — for real.**

![GNOME Shell](https://img.shields.io/badge/GNOME%20Shell-45%E2%80%9351-blue)
![License](https://img.shields.io/badge/license-GPL--3.0--or--later-green)

GNOME Shell 45–51 · Wayland and X11 · no settings of its own · no dependencies

---

## What happens

You keep one workspace per task and you turned on *current workspace only*, so
Alt+Tab stays clean. Then:

- a chat app, mail client, download manager, Steam, a CI job or an IDE build on
  **another** workspace decides it wants your attention…
- …and it shows up in **this** workspace's Alt+Tab, usually as the **first**
  entry;
- you press Enter and GNOME throws you onto that other workspace, mid-task.

It happens again every time that app pings you, and GNOME has **no setting to
stop it**. The “*window title* is ready” notification is not the annoying part
— the switcher entry is.

## What this extension does

It makes *current workspace only* mean what it says: **only windows on the
current workspace are listed**, with no exception for windows that demand
attention somewhere else.

| Switcher setting | Stock GNOME | With this extension |
|---|---|---|
| current workspace only — window switcher (Alt+Tab) | current workspace **+ attention windows from every other workspace** | current workspace only |
| current workspace only — application switcher (Super+Tab) | same leak | current workspace only |
| all workspaces | every window, everywhere | unchanged |
| sticky windows (on all workspaces) | listed | still listed |

You keep the notification. You lose the hijacked Alt+Tab.

---

## Quick start

```bash
# 1. install
git clone https://github.com/toocels/strict-workspace-switcher
cd strict-workspace-switcher && make install

# 2. log out and back in  (on X11: Alt+F2, type r, Enter)
#    GNOME Shell only scans the extensions folder at startup, so a brand new
#    extension cannot be picked up live.

# 3. turn on the switcher you want isolated (see below)
gsettings set org.gnome.shell.window-switcher current-workspace-only true

# that's it — check it came up
gnome-extensions list --enabled | grep strict-workspace-switcher
```

Installing from extensions.gnome.org (once published) is a single click and
needs no terminal. [Zip and manual installs are below.](#install)

---

## Install

### From extensions.gnome.org

Search for **Strict Workspace Switcher** and press Install. No logout needed for
updates, and it comes enabled.

### From source

```bash
git clone https://github.com/toocels/strict-workspace-switcher
cd strict-workspace-switcher
make install          # runs the unit tests, then copies the extension into
                      # ~/.local/share/gnome-shell/extensions/
```

Then reload GNOME Shell:

- **Wayland:** log out and back in. (A new extension cannot be loaded without
  one shell restart — that is a GNOME limitation, not this extension's.)
- **X11:** `Alt+F2`, type `r`, `Enter`.

Then enable it:

```bash
gnome-extensions enable strict-workspace-switcher@toocels
```

### From a zip

```bash
make pack
gnome-extensions install --force dist/strict-workspace-switcher@toocels.shell-extension.zip
# log out / back in, then
gnome-extensions enable strict-workspace-switcher@toocels
```

---

## Turn on the switchers you want isolated

The extension has no settings of its own — it makes GNOME's existing switcher
settings strict, per switcher. Turn on the ones you actually use.

**Window switcher** — what Alt+Tab is bound to on Ubuntu, Mint, Pop!_OS and any
system where *Switch applications* was rebound:

```bash
gsettings set org.gnome.shell.window-switcher current-workspace-only true
```

> GNOME Settings has **no UI for this key**. The extension's preferences page
> does, so you can flip it there instead.

**Application switcher** — super+tab by default: Settings → *Multitasking* →
*App Switching* → *Include apps from the current workspace only*, or:

```bash
gsettings set org.gnome.shell.app-switcher current-workspace-only true
```

Not sure which one your Alt+Tab uses? Whichever of these lists `<Alt>Tab`:

```bash
gsettings get org.gnome.desktop.wm.keybindings switch-windows
gsettings get org.gnome.desktop.wm.keybindings switch-applications
```

Both switches are also on the extension's preferences page (right-click the
extension in Extensions, or `gnome-extensions prefs
strict-workspace-switcher@toocels`).

---

## Verify it works

### 1. Make a window on another workspace demand attention

**Wayland or X11** — open Looking Glass (`Alt+F2`, type `lg`, `Enter`) and paste:

```js
let w = global.get_window_actors().map(a => a.meta_window)
    .find(w => !w.is_skip_taskbar() && w.get_title());
w.change_workspace_by_index(1, true);   // send it to workspace 2
w.activate(0);                          // timestamp 0 + other workspace -> demands attention
w.demands_attention                     // -> true
```

Clear it again later with `w.activate(global.get_current_time())` (focusing a
window clears the flag).

**X11 / XWayland only** — use the bundled helper, which prints the window's
EWMH state so you can see it really is demanding attention:

```bash
mkdir -p /tmp/attention-demo && nautilus /tmp/attention-demo &
tools/demo-attention-window.sh "attention-demo"
```

### 2. Press Alt+Tab without leaving your workspace

- Extension **enabled**: the window is not in the list.
- Extension **disabled**: it is in the list, first — the stock behaviour.

```bash
gnome-extensions disable strict-workspace-switcher@toocels   # looks like stock GNOME
gnome-extensions enable  strict-workspace-switcher@toocels   # strict again
```

Once installed, enable/disable is instant — no logout, so you can A/B it live.

```bash
tools/demo-attention-window.sh --clear "attention-demo"      # clean up
```

---

## What it does not do

- It does not touch the demands-attention flag, so a window that wants attention
  still raises the usual “*window title* is ready” notification while you are
  looking elsewhere.
- It does not change focus stealing prevention, so an app that grabs focus by
  other means still can (that is a [different
  mechanism](https://discourse.gnome.org/t/understanding-gnome-shell-s-focus-stealing-prevention/23434)).
- It does not touch the Overview, the dash, the workspace switcher or window
  animations.
- It never *loosens* anything: a switcher set to “all workspaces” behaves exactly
  as stock GNOME.

---

## Background: why it happens

You do not need any of this to use the extension — it is here because “why on
earth does it do that?” deserves an answer, and because it shows why no plain
setting can fix it.

Both switchers build their list from mutter's tab list
(`js/ui/altTab.js`):

```js
function getWindows(workspace) {
    const windows = global.display.get_tab_list(Meta.TabList.NORMAL_ALL, workspace);
    ...
}
```

`workspace` is the active workspace when the switcher is in *current workspace
only* mode, and `null` when it is in *all workspaces* mode. mutter's
`meta_display_get_tab_list()` (`src/core/display.c`) then does this,
unconditionally:

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
anywhere that wants attention”**. The gschema description promises “only windows
from the current workspace are shown in the switcher”; the carve-out is not
mentioned anywhere, and there is no key to disable it. The behaviour dates back
to metacity (2009) and upstream considers it intentional — see [Why isn't this
fixed upstream?](#why-isnt-this-fixed-upstream).

---

## How it works

`Meta.Display.get_tab_list()` is the single place GNOME Shell asks mutter for a
switcher list. The extension replaces it with a wrapper:

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
injected attention windows and nothing else. (The remaining entries of a
workspace-filtered list are the active workspace's own MRU list, whose windows
are by definition located on it; sticky windows pass the test either way.)

Patching at that level, rather than per popup, means:

- *Switch windows* (Alt+Tab), *Switch applications* (Super+Tab) and *Cycle
  windows* are all correct.
- `Ctrl+Alt+Tab` (the accessibility switcher) uses the same call and becomes
  consistent too.
- Third-party switchers that build their list from
  `global.display.get_tab_list(type, workspace)` inherit the fix; switchers that
  build their own list are simply unaffected.
- The wrapper chains: if another extension has wrapped `get_tab_list`, this
  extension wraps *that*, and on `disable()` it only restores its own wrapper if
  it is still the installed one, so enable/disable order cannot clobber anyone.

---

## Compatibility

- GNOME Shell **45–51**, Wayland and X11 sessions.
- Developed and tested on **GNOME Shell 51.1** (Arch Linux, Wayland).
- No dependencies, no settings of its own, no schemas, no stylesheets.

---

## Troubleshooting

**“I enabled it, but nothing changed.”**
Check it is actually loaded — on Wayland a freshly installed extension needs one
log out/in:

```bash
gnome-extensions list --enabled | grep strict-workspace-switcher
gnome-extensions info strict-workspace-switcher@toocels
```

**“The window still shows up.”**
Check the matching switcher setting (see above) — with the setting off, the
switcher deliberately lists every workspace and the extension stays out of the
way. Note that mutter clears the attention flag the moment the window is
focused (`meta_window_focus()`), so verify with a window you are *not* focused
on.

**“A sticky window shows up.”**
Windows that are on all workspaces (panels, always-on-top dashboards) are on
your workspace too, so they are kept. That is intentional.

**Where are the logs?**

```bash
journalctl --user -f -o cat | grep strict-workspace-switcher
```

---

## Uninstall

```bash
make uninstall
# or
gnome-extensions uninstall strict-workspace-switcher@toocels
```

Your GNOME switcher settings are left exactly as they were — they belong to you,
not to the extension.

---

## Development

```
metadata.json                     extension metadata (uuid, shell-version)
extension.js                      enable/disable, installs the wrapper
tabListFilter.js                  the filtering logic (no GNOME imports -> unit-tested)
prefs.js                          preferences page (GNOME's own switcher keys)
tests/tab-list-filter.test.js     unit tests, no session or display needed
tools/demo-attention-window.sh    reproduce the condition on X11/XWayland
Makefile                          install / pack / test / check / uninstall
```

```bash
make check      # validate metadata.json
make test       # run the unit tests (gjs, no GNOME session needed)
make install    # copy into ~/.local/share/gnome-shell/extensions
make pack       # build the .shell-extension.zip
```

The tests feed the wrapper a mocked tab list shaped exactly like mutter's — the
workspace's own MRU list plus the attention windows it prepends — and pin down
the contract: other workspaces gone, sticky windows kept, order preserved,
`this`/arguments forwarded, "all workspaces" mode untouched, wrappers chain.

If you add more JS modules, list them in `EXTRA` in the Makefile:
`gnome-extensions pack` only packages known filenames plus `--extra-source`
entries, and a missing module means a silently broken extension after install.

---

## FAQ

### Why isn't this fixed upstream?

Because the behaviour is deliberate: apps that ask for attention are supposed to
surface. Even in the closely related MATE/`marco` tracker, where users filed the
same complaint, the maintainer's answer was *“This behaviour is intentional …
This is by design”* — the offered fix was an option to change the **ordering** of
urgent windows, not to exclude them
([marco#824](https://github.com/mate-desktop/marco/issues/824)).

The mechanism itself is documented in mutter's own history: the 2019 commit
`d2ca5cc2` (“display: Fix inconsistent behavior with demand attention”,
[issue #523](https://gitlab.gnome.org/GNOME/mutter/-/issues/523)) explicitly
describes “a mechanism in `meta_display_get_tab_list()` which forces the windows
with the demand attention flag set to be placed first in the MRU list when
they're placed on a workspace different from the current one”.

So this extension is the pragmatic route: keep the notification, drop the
switcher entry, no compositor rebuild.

### Doesn't “current workspace only” already mean this?

It means “current workspace, plus anything that demands attention anywhere”.
The tab list is workspace-filtered first and the attention windows are prepended
afterwards, as shown [above](#background-why-it-happens).

### I want the attention window kept, but not moved to the front. Can this do that?

No — this extension removes the entry, it does not reorder it. Reordering would
mean re-implementing the switcher list order instead of filtering it.

### Is there a plain setting for this?

No. The only knobs are
`org.gnome.shell.window-switcher current-workspace-only`,
`org.gnome.shell.app-switcher current-workspace-only` and
`window-switcher app-icon-mode`. None of them influences the attention
carve-out.

### Can I do this without an extension?

Only by patching mutter: delete the `if (workspace) …` block in
`meta_display_get_tab_list()` (`src/core/display.c`) and rebuild. That is a fork
of your compositor; this extension is the same behaviour, revertible at runtime.

### Does it work with other switcher extensions?

If they ask GNOME Shell for the tab list (`get_tab_list(type, workspace)`), they
inherit the fix. If they build their own window list, they are unaffected — like
any extension in that case, check theirs before filing anything here.

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

Source references in this README are from GNOME Shell 51.1 / mutter 51 and are
quoted for explanation only; mutter and GNOME Shell are licensed under the
GPL-2.0-or-later.
