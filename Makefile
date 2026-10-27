CONFIG ?= release
CEF_PATH ?= $(HOME)/.local/share/cef
export CEF_PATH

ifeq ($(CONFIG),release)
CARGO_PROFILE_FLAG := --release
else
CARGO_PROFILE_FLAG :=
endif

.DEFAULT_GOAL := bundle
.PHONY: core shell bundle run clean

core:
	cd core && cargo build $(CARGO_PROFILE_FLAG)

shell: core
	cd shell && swift build -c $(CONFIG)

bundle:
	CONFIG=$(CONFIG) scripts/bundle.sh

run: bundle
	open build/Mini.app

clean:
	rm -rf build
	cd core && cargo clean
	cd shell && swift package clean
