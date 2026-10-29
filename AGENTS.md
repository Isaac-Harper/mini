# Mini

A minimal personal macOS browser: native Swift shell (AppKit window, SwiftUI sidebar, Liquid Glass) around Chromium via CEF, embedded from a Rust core using the `cef` crate (tauri-apps/cef-rs). Arc-style vertical sidebar with nested (tree) tabs. Single main window (plus little windows for outside links and torn-off tabs), spaces with separate profiles, no extensions, sync or accounts. Target: macOS 26+, Apple Silicon. README.md has the feature list and build steps.

This file is the onboarding summary. Detail lives in `docs/agents/`:

| File | Covers |
| --- | --- |
| `docs/agents/cef-and-core.md` | Rust core sources, injected page scripts, C ABI rules, verified CEF 156 and toolchain facts, ad blocking |
| `docs/agents/shell-ui.md` | Swift coordinator, keys and menus, window and page card, sidebar, command bar, overlays, page features, AppKit facts |
| `docs/agents/tabs-and-undo.md` | Tab kinds, tab undo, auto-archive and idle fade, split view, drag and drop, little windows, tear-off and dock |
| `docs/agents/spaces-and-session.md` | Spaces and profiles, space colors, space swipe, session.json shape and migrations, history |
| `docs/agents/haptics.md` | The haptic map and detent rules |
| `docs/agents/signing-release-codecs.md` | bundle.sh and Makefile, signing traps, hardened runtime, release script, proprietary-codecs CEF build |
| `docs/agents/testing-harness.md` | Gates, background test-instance rules, harness traps |

Read the matching doc before changing an area, and update it in the same commit when the change invalidates it.

## Architecture

```
Mini.app/Contents/MacOS/Mini            Swift executable (shell/), statically links libmini_core.a
  main.swift: MiniApplication (NSApplication + CefAppProtocol) -> mini_initialize -> mini_run_message_loop -> mini_shutdown
Mini.app/Contents/Frameworks/
  Chromium Embedded Framework.framework   loaded at runtime by cef_load_library (never linked)
  Mini Helper{, (GPU), (Renderer), (Plugin), (Alerts)}.app   all copies of the Rust mini-helper binary
```

- Swift owns: window, sidebar, tab tree, selection, command bar, menus and key equivalents, focus decisions, session persistence. Tab ids are minted in Swift.
- Rust owns: CEF init/shutdown, the tab-id -> Browser map, every CEF handler (display, load, life span, request, keyboard, focus, download, permission, context menu). It never draws UI.
- The boundary is the C ABI in `core/include/mini_core.h`, nothing else. Rust calls back through the `MiniCallbacks` function-pointer table; Swift calls `mini_*` functions.
- Page-side features (login detection, WebAuthn suppression, notifications, editable focus, media, theme color, horizontal scroll room) are scripts injected at `on_load_start` that report over one console channel keyed by a per-process token.
- Each tab has a `BrowserHostView`; CEF creates the windowed (non-OSR) browser NSView inside it. `ShellController.refreshDisplayedTabs` is the only code that shows or hides host views.
- Spaces: `ShellController.spaces` holds `Space` objects, each with its own `TabStore` and CEF request context (`Profile/Default` for the default-profile space, `Profile/Spaces/<id>` for the rest); `store` is always `currentSpace.store`.
- Browsers are created lazily: restored tabs have no browser until first selected (or shown as the other side of a split).

## Invariants

Each line is expanded in the doc named at its end.

- Everything CEF runs on the main thread; never multi_threaded_message_loop or external_message_pump. (cef-and-core)
- NSApp is `MiniApplication` before `mini_initialize`; nothing touches `NSApplication.shared` earlier. (cef-and-core)
- Quit goes through `MiniApplication.terminate(_:)`: save, close all browsers, wait for `all_browsers_closed`, quit the loop; never `exit()` with live browsers. (cef-and-core)
- Browsers use the Alloy runtime style; the shell draws all chrome. (cef-and-core)
- The C header is the contract: change it, then both sides, in the same commit. (cef-and-core)
- Every `mini_browser_*` call needs `Tab.browserState == .created`; Rust panics otherwise. Tab ids are never reused. (cef-and-core)
- CEF never opens a top-level window: popups go into a tab or little window, a second launch goes through `app_relaunched`; only DevTools and Chromium's PiP window are exceptions. (cef-and-core)
- Popups with an opener become child tabs via `popup_requested`; opener-less new-tab links use `open_tab_requested`. (cef-and-core)
- Login values are never logged, persisted or echoed, and the fill origin is always derived browser-side. Notification titles, bodies and tags are never logged. (cef-and-core)
- App shortcuts beat the page through `pre_key_event`, except Edit-menu shortcuts; Cmd-Z goes to tab undo only when the page has no editable focus. (shell-ui)
- Every undoable tab action goes through `performUndoable` on the dedicated `tabUndoManager`, one explicit group per action. (tabs-and-undo)
- Tab kind follows the tree: a saved root's whole subtree is saved; closing a saved or pinned tab resets it, `remove` is the real close. (tabs-and-undo)
- Auto-archive never closes the selected tab, its split partner, playing, pinned, saved or folded tabs, and closes a parent only after all its children; with Close the Day on it archives whole expired day groups instead of idle tabs. (tabs-and-undo)
- A tab is in at most one split; split focus follows clicks, and only the selected tab may take CEF focus. (tabs-and-undo)
- At most one Player tab per space (`TabStore.playerTab`, pinned kind, outside `pinnedTabs`); only it ever docks into the sidebar. (tabs-and-undo)
- Little-window tabs live only in `ShellController.littleWindows`, never in a store, session.json, the archive or Now Playing. (tabs-and-undo)
- Promote, tear-off and dock move the same live `Tab` and browser, with no reload. (tabs-and-undo)
- Menu commands act on the key window's tab; find and Fill Password are main-window only. (tabs-and-undo)
- Only the current space's store drives the window; background spaces keep running. (spaces-and-session)
- The default-profile space and the last space are never deletable; nothing outside `Profile/Spaces` is ever deleted. (spaces-and-session)
- session.json older shapes load and are rewritten in the current shape; the old shapes are never written. (spaces-and-session)
- `Haptics.swift` is the only haptic caller, and only direct-manipulation paths call it. (haptics)
- Never run `--use-mock-keychain` against the real profile; local builds sign with a stable certificate identity. (signing-release-codecs)
- Releases ship the stock CEF only; `check-stock-cef.sh` guards it. (signing-release-codecs)
- Tests never touch the real profile, session or UserDefaults, run in the background only, and never commit debug hooks. (testing-harness)
- Style: no comments unless a genuine trap, full-word names, no em/en dashes, no AI attribution anywhere.

## File map

Rust core (`core/`, detail in cef-and-core.md):

- `core/include/mini_core.h`: the C ABI.
- `core/Cargo.toml`, `core/.cargo/config.toml`: workspace (edition 2024, `cef = "=156.2.0"`, release `panic = "abort"`), deployment target pinned to 26.0.
- `core/mini-helper/`: helper executable (sandbox init + `cef_execute_process`).
- `core/mini-core/src/lib.rs` (the `src/` entries below are in `core/mini-core/`): the exported ABI functions and `#[repr(C)]` mirrors of the header types.
- `src/application.rs`: `MiniApp`; second-launch relaunch handler.
- `src/state.rs`: main-thread core state (callbacks, request contexts per space, `TabState` per tab, pending ids).
- `src/client.rs`: `MiniClient` per tab with every CEF handler; `DevToolsClient`.
- `src/favicon.rs`: favicon download as PNG.
- `src/permissions.rs`: permission handler and pending requests.
- `src/authentication.rs`: HTTP auth on the IO thread.
- `src/login.rs`: login-form script, console signal token, fill scripts.
- `src/webauthn.rs`: WebAuthn suppression script.
- `src/notifications.rs`: Web Notifications shim.
- `src/editable_focus.rs`: editable-focus script and rule.
- `src/media.rs`: playing state, media metadata and artwork.
- `src/theme_color.rs`: theme-color script and parser.
- `src/horizontal_scroll.rs`: page horizontal scroll room for swipe navigation.
- `src/resource_requests.rs`: ad block request cancelling (IO thread).
- `src/ad_blocking/`: Brave `adblock` engine, lists, resources, matching.
- `src/context_menu.rs`: context menu params to Swift and the item ABI calls.
- `src/site_data.rs`: Clear Data for This Site.
- `src/registrable_domain.rs`: registrable domain from the public suffix list (`psl`), unit tested.
- `src/navigation.rs`: session history visitor and `history.go` offsets.
- `src/downloads.rs`: download destination naming and progress.
- `src/page_source.rs`: main-frame source for View Source.

Swift shell (`shell/`; sources in `shell/Sources/Mini/`):

- `Package.swift`, `Sources/CMiniCore/module.modulemap`: SwiftPM manifest and the module over `mini_core.h`. (cef-and-core)
- `main.swift`: `MiniApplication.shared` first, then init / run loop / shutdown. (cef-and-core)
- `MiniApplication.swift`: NSApplication subclass with the CrApp/CefApp protocols; quit flow. (cef-and-core)
- `BrowserEngine.swift`: the `MiniCallbacks` table. (cef-and-core)
- `AppDelegate.swift`: launch, dock reopen, URLs from other apps. (shell-ui)
- `ShellController.swift`: central coordinator. (shell-ui)
- `BrowserEvents.swift`: every engine callback. (shell-ui)
- `ShellCommands.swift`: menu actions and validation. (shell-ui)
- `MenuKeyEquivalents.swift`: page key events to menu items; Cmd-Z detection. (shell-ui)
- `MainMenu.swift`: the main menu, built in code. (shell-ui)
- `BrowserHostView.swift`: the view CEF embeds into. (shell-ui)
- `MainWindowController.swift`: split view window, page card, `WebAreaView`, split divider, loading line, empty page. (shell-ui)
- `WindowToolbar.swift`: toolbar items inside the sidebar. (shell-ui)
- `WindowControlsCluster.swift`: controls while the sidebar is collapsed. (shell-ui)
- `PeekSidebarController.swift`: peek sidebar from the left edge. (shell-ui)
- `SidebarView.swift`, `TabRowView.swift`, `PinnedTabsView.swift`: SwiftUI sidebar, rows, tiles, address pill, space buttons. (shell-ui)
- `FadingTruncation.swift`: faded title ends for SwiftUI text and the little window field. (shell-ui)
- `GlassTooltip.swift`: the one glass tooltip for SwiftUI and AppKit controls. (shell-ui)
- `HoverHighlight.swift`: the shared hover highlight for SwiftUI and AppKit controls. (shell-ui)
- `InterfaceMetrics.swift`: every sidebar and command bar metric on the 4pt grid, and the shared fonts. (shell-ui)
- `SiteTintView.swift`: sidebar tint from space color, page theme color and the evening tint. (shell-ui)
- `Sources/MiniRules/FaviconTone.swift`: favicon luminance and coverage, and when a backing plate is needed, unit tested. (shell-ui)
- `Sources/MiniRules/UnreadTitle.swift`, `UnreadBadgeView.swift`: unread counts parsed from titles (pure, unit tested) and the favicon badge. (shell-ui)
- `Sources/MiniRules/AddressEmphasis.swift`: address pill split around the registrable domain from an injected resolver (the core's public suffix list), unit tested. (shell-ui)
- `AddressPillBadges.swift`: the pill's caption chips (preview). (shell-ui)
- `Sources/MiniRules/PreviewDeployment.swift`, `PreviewSwitching.swift`: preview deployment hosts and the preview/production switch from history, unit tested. (shell-ui)
- `Sources/MiniRules/EveningTint.swift`: pure evening tint strength curve, in its own target so `Tests/MiniRulesTests` can test it without linking the app. (shell-ui)
- `SidebarKeyboard.swift`: sidebar keyboard focus. (shell-ui)
- `SidebarSelection.swift`, `Sources/MiniRules/RowSelection.swift`: multi-select rows (pure range and toggle rules, unit tested) and the group actions. (tabs-and-undo)
- `Downloads.swift`: downloads model and sidebar rows. (shell-ui)
- `NowPlaying.swift`, `DominantColor.swift`: Now Playing row, mute button, artwork tint. (shell-ui)
- `PlayerDock.swift`, `PlayerSlotView.swift`, `Sources/MiniRules/PlayerSlot.swift`: the Player tab's sidebar slot, the docked browser's child panel and hover controls, the dock page scripts; pure phase and presentation rules, unit tested. (shell-ui)
- `AirPlay.swift`: AirPlay video handoff, the row's route picker, the sound output fallback menu. (shell-ui)
- `WeatherService.swift`, `WeatherRowView.swift`, `WeatherWeekView.swift`: weather row and 7-day popover. (shell-ui)
- `CommandBarController.swift`, `CommandBarModel.swift`, `CommandSuggestionsView.swift`: the command bar. (shell-ui)
- `PastedLinks.swift`: pasted link lists in the command bar. (shell-ui)
- `CommandActions.swift`, `Sources/MiniRules/FuzzyMatch.swift`, `Sources/MiniRules/KeyEquivalentText.swift`: the command bar's `>` action list from the main menu, unit tested matching. (shell-ui)
- `SearchSuggestions.swift`: Google suggestions. (shell-ui)
- `URLInput.swift`: input to URL or search. (shell-ui)
- `OverlayAnimation.swift`: shared overlay appear and disappear. (shell-ui)
- `FindBarController.swift`: find in page. (shell-ui)
- `StatusBubbleController.swift`: link hover bubble. (shell-ui)
- `ToastController.swift`: transient toast. (shell-ui)
- `CrashOverlayController.swift`: crashed page overlay. (shell-ui)
- `SitePromptController.swift`, `SitePromptViews.swift`: permission and auth cards. (shell-ui)
- `LoginFillController.swift`, `LoginFillCardView.swift`: password fill card. (shell-ui)
- `PageContextMenu.swift`: native page context menu. (shell-ui)
- `NavigationHistory.swift`: back/forward history menus. (shell-ui)
- `SourceWindowController.swift`, `Sources/MiniRules/SourceHighlighting.swift`: View Source window and its HTML/CSS/JS tokenizer, unit tested. (shell-ui)
- `SwipeNavigationController.swift`: two-finger swipe back and forward. (shell-ui)
- `ShellFullscreen.swift`: page fullscreen. (shell-ui)
- `NotificationsController.swift`: macOS notification delivery. (shell-ui)
- `SitePreferences.swift`: per-origin permissions, ad block exemptions, zoom levels. (shell-ui)
- `FaviconCache.swift`: per-host favicon cache. (shell-ui)
- `DefaultBrowser.swift`: default-browser registration. (shell-ui)
- `Tab.swift`: tab node. (tabs-and-undo)
- `TabStore.swift`: pinned tabs, tab tree, selection, splits. (tabs-and-undo)
- `SavedTabsSection.swift`: Saved section and its drop row. (tabs-and-undo)
- `TabUndo.swift`: snapshots and tab undo. (tabs-and-undo)
- `UndoToast.swift`: the sidebar's undo toast after close, archive and tear-off. (tabs-and-undo)
- `TabArchive.swift`: archive policy, idle fade, archive.json. (tabs-and-undo)
- `CloseTheDay.swift`, `DayFoldRow.swift`, `Sources/MiniRules/DayClosing.swift`: Close the Day (daily fold of untouched tabs into dated groups; pure day and fold rules unit tested) and the group header row. (tabs-and-undo)
- `SidebarDragging.swift`: sidebar drag and drop. (tabs-and-undo)
- `TabTearOff.swift`: tear-off preview, tear-off and dock tracking. (tabs-and-undo)
- `LittleWindowController.swift`: little window. (tabs-and-undo)
- `Spaces.swift`: `Space`, symbols, cache paths, `TabIdentifierMint`. (spaces-and-session)
- `SpaceColors.swift`: the space color palette. (spaces-and-session)
- `ShellSpaces.swift`: switch, create, rename, delete spaces. (spaces-and-session)
- `SpaceSwipe.swift`: two-finger swipe between spaces. (spaces-and-session)
- `SessionStore.swift`: session.json. (spaces-and-session)
- `HistoryStore.swift`: per-space SQLite history and frecency. (spaces-and-session)
- `ShellHistory.swift`, `HistoryWindowController.swift`: History menu and window. (spaces-and-session)
- `Haptics.swift`: haptic moments and pure detent rules. (haptics)

Bundle and scripts (detail in signing-release-codecs.md):

- `bundle/AppIcon-1024.png`, `bundle/AppIcon.icns`: app icon source and committed icns.
- `bundle/Info.plist`: main app plist template.
- `bundle/Mini.entitlements`, `bundle/MiniHelper.entitlements`: app and helper entitlements.
- `scripts/bundle.sh`, `Makefile`: build, bundle, sign; `make install`.
- `scripts/cef-path.sh`: picks the codecs CEF or the stock one for local builds.
- `scripts/build-cef-codecs.sh`: builds the proprietary-codecs CEF from source.
- `scripts/check-stock-cef.sh`: release guard against the codecs build.
- `scripts/release.sh`: notarized GitHub release.

## Verification

- `make run` builds, bundles, signs and launches. Gates: app launches, page renders in the content card, tabs create/switch/close/nest, Cmd shortcuts work while a page has focus, Cmd-Q quits cleanly (no crash report), session restores on relaunch.
- `cargo clippy` and `cargo test` in `core/`, `swift build` in `shell/`; `make test` runs `cargo test` and the Swift `MiniRulesTests`.
- Scenario testing runs a separate scratch-bundle instance in the background; rules in testing-harness.md.

## Status

v0.2.0 is the latest release (signed, notarized, stock CEF): spaces, saved tabs, undo, tear-off, space colors and swipe, haptics, history, context menu, fullscreen, peek sidebar, evening tint and the rest since v0.1.0. Local builds and `make install` use the proprietary-codecs CEF when installed; releases never do. `git log v0.2.0..HEAD` lists unreleased work.
