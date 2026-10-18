# Changelog

All notable changes to this extension are documented here.
This project adheres to [Semantic Versioning](https://semver.org/).

## [1.0.0] — 2026-10-18

Initial release.

- Wrap `Meta.Display.get_tab_list()` so a workspace-filtered tab list never
  contains windows located on another workspace, removing the
  demands-attention exception that mutter adds unconditionally.
- "All workspaces" mode (`workspace == null`) is left untouched.
- Sticky ("on all workspaces") windows are still listed.
- Preferences page on top of GNOME's own switcher settings, including the
  window-switcher key that GNOME Settings does not expose.
- `tools/demo-attention-window.sh` to reproduce the condition on X11/XWayland.

[1.0.0]: https://github.com/toocels/strict-workspace-switcher/releases/tag/v1.0.0
