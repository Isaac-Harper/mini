CONFIG ?= release
CEF_PATH ?= $(HOME)/.local/share/cef
export CEF_PATH

ifeq ($(CONFIG),release)
CARGO_PROFILE_FLAG := --release
else
CARGO_PROFILE_FLAG :=
endif

.DEFAULT_GOAL := bundle
.PHONY: core shell bundle run install clean

core:
	cd core && cargo build $(CARGO_PROFILE_FLAG)

shell: core
	cd shell && swift build -c $(CONFIG)

bundle:
	CONFIG=$(CONFIG) scripts/bundle.sh

run: bundle
	open build/Mini.app

LSREGISTER := /System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister
MINI_PROCESSES := Mini.app/Contents/(MacOS/Mini|Frameworks/Mini Helper)

install: bundle
	@if pgrep -f '$(MINI_PROCESSES)' >/dev/null; then osascript -e 'tell application id "dev.isaacharper.mini" to quit'; fi
	@for attempt in $$(seq 1 60); do pgrep -f '$(MINI_PROCESSES)' >/dev/null || exit 0; sleep 0.5; done; echo "Mini is still running" >&2; exit 1
	rm -rf /Applications/Mini.app
	ditto build/Mini.app /Applications/Mini.app
	$(LSREGISTER) -f /Applications/Mini.app
	open /Applications/Mini.app

clean:
	rm -rf build
	cd core && cargo clean
	cd shell && swift package clean
