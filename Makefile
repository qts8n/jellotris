PYTHON ?= python3
LOVE ?= love
VERSION ?= 0.2.0
LOVE_WINDOWS ?=
LOVE_MACOS ?=
LOVE_LINUX ?=
RCEDIT ?=
BUNDLE_ID ?= org.jellotris.game

.DEFAULT_GOAL := help
.PHONY: help run test test-headless test-build smoke icons love linux windows macos clean

help:
	@echo 'run           Play from source'
	@echo 'test          Run the LÖVE integration suite'
	@echo 'test-headless Run it with SDL offscreen rendering'
	@echo 'test-build    Check packaging and native archive structure'
	@echo 'smoke         Start and render the packaged game, then exit'
	@echo 'icons         Re-render PNG / ICO / ICNS icons using LÖVE'
	@echo 'love          Build dist/jellotris-$(VERSION).love'
	@echo 'linux         Build a Linux tarball (optional LOVE_LINUX=/path/to/squashfs-root)'
	@echo 'windows       Build a Windows ZIP (LOVE_WINDOWS=/path/to/extracted-runtime)'
	@echo 'macos         Build a macOS ZIP (LOVE_MACOS=/path/to/love.app)'
	@echo 'clean         Remove generated build/ and dist/ directories'

run:
	"$(LOVE)" .

test:
	"$(LOVE)" . --test

test-headless:
	ALSOFT_DRIVERS=null SDL_VIDEODRIVER=offscreen "$(LOVE)" . --test

test-build:
	$(PYTHON) -m unittest discover -s tests -p 'test_*.py' -v

smoke: love
	"$(LOVE)" "dist/jellotris-$(VERSION).love" --smoke

icons:
	$(PYTHON) tools/build.py icons --love "$(LOVE)"

love:
	$(PYTHON) tools/build.py love --version "$(VERSION)"

linux:
	$(PYTHON) tools/build.py linux --version "$(VERSION)" $(if $(LOVE_LINUX),--runtime "$(LOVE_LINUX)")

windows:
	$(PYTHON) tools/build.py windows --version "$(VERSION)" $(if $(LOVE_WINDOWS),--runtime "$(LOVE_WINDOWS)") $(if $(RCEDIT),--rcedit "$(RCEDIT)")

macos:
	$(PYTHON) tools/build.py macos --version "$(VERSION)" --bundle-id "$(BUNDLE_ID)" $(if $(LOVE_MACOS),--runtime "$(LOVE_MACOS)")

clean:
	$(PYTHON) tools/build.py clean
