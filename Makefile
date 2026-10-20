# Strict Workspace Switcher — build helpers
#
#   make install    copy the extension into ~/.local/share/gnome-shell/extensions
#                   (runs the tests first; same as ./install.sh)
#   make uninstall  remove the installed copy (same as ./uninstall.sh)
#   make pack       build dist/<uuid>.shell-extension.zip (for extensions.gnome.org
#                   or `gnome-extensions install`)
#   make test       run the unit tests (gjs, no session needed)
#   make check      sanity-check metadata.json

UUID      := strict-workspace-switcher@toocels
TARGET    := $(HOME)/.local/share/gnome-shell/extensions/$(UUID)
SOURCES   := metadata.json extension.js tabListFilter.js
TESTS     := tests/tab-list-filter.test.js
# Modules beyond metadata.json/extension.js must be listed explicitly,
# otherwise gnome-extensions pack leaves them out of the zip.
EXTRA     := --extra-source=tabListFilter.js

.PHONY: all check test install uninstall pack clean

all: check test

check:
	@python3 -c "import json; json.load(open('metadata.json')); print('metadata.json: ok')"
	@for f in $(SOURCES); do test -f "$$f" || { echo "missing $$f"; exit 1; }; done

test:
	@gjs --module $(TESTS)

install: check test
	@./install.sh

uninstall:
	@./uninstall.sh

pack: check test
	@rm -rf dist
	@mkdir -p dist
	@gnome-extensions pack --force $(EXTRA) --out-dir dist .
	@echo
	@unzip -l dist/$(UUID).shell-extension.zip

clean:
	rm -rf dist
