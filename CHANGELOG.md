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
- `install.sh` / `uninstall.sh` for the current user, no make or root required.

[1.0.0]: https://github.com/toocels/strict-workspace-switcher/releases/tag/v1.0.0
