# Mini

A minimal personal macOS browser: native Swift shell (AppKit window, SwiftUI sidebar, Liquid Glass) around Chromium via CEF, embedded from a Rust core using the `cef` crate (tauri-apps/cef-rs). Arc-style vertical sidebar with nested (tree) tabs. Single window, single profile, no extensions, sync or accounts. Target: macOS 26+, Apple Silicon. README.md has build and run steps.

## Architecture

```
Mini.app/Contents/MacOS/Mini            Swift executable (shell/), statically links libmini_core.a
  main.swift: MiniApplication (NSApplication + CefAppProtocol) -> mini_initialize -> mini_run_message_loop -> mini_shutdown
Mini.app/Contents/Frameworks/
  Chromium Embedded Framework.framework   loaded at runtime by cef_load_library (never linked)
  Mini Helper{, (GPU), (Renderer), (Plugin), (Alerts)}.app   all copies of the Rust mini-helper binary
```

- Swift owns: window, sidebar, tab tree, selection, command bar, menus and key equivalents, focus decisions, session persistence. Tab ids are minted in Swift.
- Rust owns: CEF init/shutdown, the tab-id -> Browser map, every CEF handler (display, load, life span, request, keyboard, focus, download). It never draws UI.
- The boundary is the C ABI in `core/include/mini_core.h`, nothing else. Rust calls back through the `MiniCallbacks` function-pointer table; Swift calls `mini_*` functions.
- Each tab has a `BrowserHostView` (NSView). CEF creates the windowed (non-OSR) browser NSView as its subview; the host view sizes subviews to its bounds. Switching tabs swaps which host view is visible and calls `mini_browser_set_hidden`.
- Browsers are created lazily: restored tabs have no browser until first selected.

## Invariants

- Everything CEF runs on the main thread (CEF UI thread = main thread on macOS, `cef_run_message_loop` drives NSApp). Never use multi_threaded_message_loop or external_message_pump.
- NSApp must be `MiniApplication` (conforming to ObjC protocols named CrAppProtocol, CrAppControlProtocol, CefAppProtocol) before `mini_initialize`. Nothing may touch `NSApplication.shared` earlier.
- Quit flows through `MiniApplication.terminate(_:)`: save session, `mini_close_all_browsers`, wait for `all_browsers_closed`, then `mini_quit_message_loop`. Never `exit()` with live browsers.
- Browsers use the Alloy runtime style (content only, no Chrome UI); the shell draws all chrome.
- App shortcuts beat the page: `pre_key_event` hands Cmd/Ctrl key-downs to Swift, which runs matching browser-command menu items and consumes them. Edit-menu shortcuts (copy, paste, undo, select all) are never consumed there.
- Popups with an opener are parented into a new child tab via `popup_requested` (keeps OAuth popups working); opener-less new-tab links use `open_tab_requested`.
- Login fill: password and username values from the shell are never logged, persisted or echoed (including under `MINI_ADBLOCK_LOG`); Rust zeroizes the script strings it builds from them. The origin passed to `login_field_focused` and checked by `mini_fill_login` is always derived browser-side from the frame's committed URL (http/https only); nothing in the page's console signal except the frame id is trusted, and the frame id is verified with `frame_by_identifier`.
- The C header is the contract: change it, then both sides, in the same commit.
- Style: no comments unless a genuine trap, full-word names, no em/en dashes, no AI attribution anywhere.

## File map

- `core/include/mini_core.h`: the C ABI.
- `core/Cargo.toml`: workspace (edition 2024, `cef = "=156.2.0"`, release `panic = "abort"`). `core/.cargo/config.toml` pins `MACOSX_DEPLOYMENT_TARGET=26.0` so C deps (ring) do not target the SDK version.
- `core/mini-core/`: Rust staticlib (`libmini_core.a`) implementing the ABI.
  - `src/lib.rs`: the `#[unsafe(no_mangle)]` ABI functions and the `#[repr(C)]` mirrors of the header types; library loader static.
  - `src/state.rs`: main-thread `thread_local` state (callbacks table, tab id -> `TabState` with `Option<Browser>` + pending url/focus/hidden/close + favicon generation, pending popup ids, reported download ids, closing-all flag); the global request-id counter shared by permissions and auth.
  - `src/client.rs`: `MiniClient` (one per tab, carries the tab id) and the display, load (cosmetic injection at `on_load_start`), life span, request (open-url, auth, resource handler), keyboard, focus and download handlers; `DevToolsClient` (no handlers) for devtools windows. Tab close dismisses pending permissions and cancels pending auth.
  - `src/favicon.rs`: `download_image` of the first favicon URL, PNG at scale 2 via `Image::as_png`; per-tab generation drops stale or closed-tab results.
  - `src/permissions.rs`: `MiniPermissionHandler`; CEF media and prompt bits <-> `MiniPermission` bits; pending requests keyed by request id (main thread). Origins are sent as `scheme://host[:port]`.
  - `src/authentication.rs`: `auth_credentials` runs on the IO thread: callback stored in a `Mutex` map, `auth_requested` delivered by a task posted to the UI thread.
  - `src/login.rs`: login-form script (injected into every frame at `on_load_start`, regardless of ad block state; it never signals on focus, only when `mini_request_login_fill` runs its request), the console signal `<token>:login:<frame_id>` (128-bit per-process token from `/dev/urandom`, sent through a `console.debug` captured at injection, consumed in `on_console_message` so it never reaches devtools), `mini_request_login_fill` and `mini_fill_login` scripts (values as escaped JSON literals, native `HTMLInputElement` value setter, `input` + `change` events, never submits). Page-side state lives on `window[Symbol.for('mini-login-' + token)]`.
  - `src/resource_requests.rs`: `MiniResourceRequestHandler` (IO thread), `on_before_resource_load` returns `CANCEL` for ad block matches.
  - `src/ad_blocking/`: Brave `adblock` engine. `mod.rs` shared state (engine `RwLock<Option<Arc<Engine>>>`, enabled `AtomicBool`, exempt hosts) and the background loader thread; `lists.rs` list URLs, 7-day refresh, download (ureq + rustls), build, `engine.dat` (de)serialization; `resources.rs` scriptlet/redirect resources; `matching.rs` CEF resource type mapping, network decision, cosmetic script. `MINI_ADBLOCK_LOG=1` logs loads and every cancelled request to stderr.
  - `src/downloads.rs`: `~/Downloads/<name>` destination with `name (1).ext` uniquifying (unit tested).
- `core/mini-helper/`: Rust helper executable (sandbox init + `cef_execute_process`).
- `shell/Package.swift`: SwiftPM manifest; links `core/target/<config>/libmini_core.a` with `-dead_strip`, `-lc++`, `-lobjc`.
- `shell/Sources/CMiniCore/module.modulemap`: system-library module pointing at `core/include/mini_core.h` (no header copy).
- `shell/Sources/Mini/main.swift`: creates `MiniApplication.shared` first, creates Profile/ and Filters/, then `mini_initialize` / run loop / shutdown.
- `shell/Sources/Mini/MiniApplication.swift`: NSApplication subclass with the CrApp/CefApp protocols; `terminate` starts the quit flow.
- `shell/Sources/Mini/AppDelegate.swift`: builds the shell, menu and window at launch; dock reopen; URLs from other apps (queued until launch).
- `shell/Sources/Mini/BrowserEngine.swift`: the `MiniCallbacks` table; C trampolines hop to the main-actor shell.
- `shell/Sources/Mini/ShellController.swift`: central coordinator: launch, tab store observer, browser lifecycle, focus model.
- `shell/Sources/Mini/BrowserEvents.swift`: ShellController extension handling every engine callback.
- `shell/Sources/Mini/ShellCommands.swift`: menu actions and validation (extension of ShellController).
- `shell/Sources/Mini/MenuKeyEquivalents.swift`: matches `pre_key_event` NSEvents to main-menu items, excluding standard edit actions.
- `shell/Sources/Mini/MainMenu.swift`: the main menu, built in code.
- `shell/Sources/Mini/Tab.swift`: tab node (observable) with favicon image, pinned URL, host view and browser state.
- `shell/Sources/Mini/BrowserHostView.swift`: NSView that CEF embeds the browser view into; sizes subviews to bounds.
- `shell/Sources/Mini/TabStore.swift`: pinned tabs (flat) plus the tab tree, selection and tree operations; id minting. Closing a pinned tab swaps in a fresh unloaded Tab (new id) at its pinned URL.
- `shell/Sources/Mini/SessionStore.swift`: session.json encode/restore and debounced saves; `pinnedTabs` and `selectedPinnedIndex` are optional so older files still load.
- `shell/Sources/Mini/MainWindowController.swift`: window built on NSSplitViewController (native floating glass sidebar item, autosaved as `MainSplitView`), web content item with `automaticallyAdjustsSafeAreaInsets` and an NSBackgroundExtensionView around `webAreaView` (host views live there).
- `shell/Sources/Mini/WindowToolbar.swift`: NSToolbar whose only items (sidebar toggle, back, forward) sit before `.sidebarTrackingSeparator`, so they render inside the sidebar next to the traffic lights.
- `shell/Sources/Mini/OverlayAnimation.swift`: shared appear (fade plus spring scale, fade only with Reduce Motion) and disappear for overlays.
- `shell/Sources/Mini/SidebarView.swift`, `TabRowView.swift`, `PinnedTabsView.swift`: SwiftUI sidebar content (glass address pill with reload/stop, `SidebarMetrics` row sizes, pinned glass tiles).
- `shell/Sources/Mini/SitePreferences.swift`: per-origin permission decisions (permissions.json) and ad block exempt hosts (adblock-exempt.json).
- `shell/Sources/Mini/SitePromptController.swift`, `SitePromptViews.swift`: per-tab queued permission and HTTP auth cards over the web card; `FaviconView`.
- `shell/Sources/Mini/LoginFillController.swift`, `LoginFillCardView.swift`: password fill card, shown only on Cmd-\ (Fill Password) via `mini_request_login_fill`, never automatically (AppKit NSTextField/NSSecureTextField with username/password content types so macOS Passwords AutoFill attaches); values are never stored and are cleared on every close.
- `shell/Sources/Mini/DefaultBrowser.swift`: default-browser check and registration for http and https.
- `shell/Sources/Mini/CommandBarController.swift`, `CommandBarModel.swift`, `CommandSuggestionsView.swift`: the floating command bar (760pt glass panel, clamped to window width minus 80, open/search row first then matching tabs, recent tabs on empty Cmd-T, Cmd-Return opens in background).
- `shell/Sources/Mini/FindBarController.swift`: find-in-page capsule.
- `shell/Sources/Mini/URLInput.swift`: input to URL or search (search template constant lives here).
- `bundle/Info.plist`: main app plist template (`NSPrincipalClass` `Mini.MiniApplication`, http/https URL types).
- `scripts/bundle.sh`, `Makefile`: build Rust + Swift, assemble and sign `build/Mini.app`. Env: `CONFIG` (release|debug), `CEF_PATH`, `MINI_SIGN_IDENTITY` (default: first Developer ID Application or Apple Development identity, else `-` ad-hoc with a warning), `SKIP_SHELL=1` (bundle without the Swift binary; the app itself is then left unsigned). Helper plists are generated by the script.

## Verified external facts

- `cef` crate 156.2.0+156.0.14. `cef-dll-sys` downloads CEF into `$CEF_PATH/<version>/` (Makefile sets `CEF_PATH=$HOME/.local/share/cef`) and builds `libcef_dll_wrapper` with cmake + Ninja (both from Homebrew).
- `LibraryLoader::new(exe, helper)` resolves the framework at `../Frameworks/` (main) or `../../..` (helper) relative to the executable; `cef::sandbox::Sandbox` loads `libcef_sandbox.dylib` from the framework and must init first in helpers.
- Call `cef::api_hash(sys::CEF_API_VERSION_LAST, 0)` after loading the library and before any other CEF call.
- objc4 `conformsToProtocol:` matches protocols by name, so Swift `@objc(CefAppProtocol)` protocols satisfy CEF's checks.
- CEF lands at `$HOME/.local/share/cef/156.0.14/cef_macos_aarch64/` (minimal distribution); the framework is `Chromium Embedded Framework.framework` in that dir. `bundle.sh` derives `156.0.14` from the `cef-dll-sys` version in `core/Cargo.lock`. The wrapper build lands under `core/target/<profile>/build/cef-dll-sys-*/out/`.
- `cargo rustc --release -p mini-core -- --print native-static-libs` prints `-lc -lm -liconv -framework AppKit -framework Foundation -framework CoreFoundation -lobjc -lSystem` (`-liconv` arrived with the ad block dependencies). The Swift link also needs `-lc++` (libcef_dll_wrapper is C++) and dead stripping (`-Wl,-dead_strip`, SwiftPM's default): the `cef` crate always compiles wrappers for `cef_sandbox_initialize`/`cef_sandbox_destroy`, which only exist in `libcef_sandbox.dylib`, so a link without dead stripping fails on those two symbols. Verified by linking an ObjC test app.
- Threads: CEF calls `auth_credentials`, `resource_request_handler` and `on_before_resource_load` on the IO thread; everything else Mini implements runs on the UI (main) thread. Swift callbacks are only ever invoked from UI-thread code; the `thread_local` core state panics if touched elsewhere.
- `adblock` 0.13.3: the default `single-thread` feature makes `Engine` neither `Send` nor `Sync`; Mini uses `default-features = false` + `embedded-domain-resolver`, `full-regex-handling`. `Engine::serialize` stores filters only, not resources, so resources are re-attached (`use_resources`) after every `deserialize`. A serialized engine is ~8.5 MB; the full lists are ~6.5 MB.
- uBO's scriptlets are now ES modules (`src/js/resources/scriptlets.js` + imports) that adblock's resource assembler cannot parse (its scriptlet parser is deprecated, old format only). Mini instead downloads Ghostery's uBO-derived bundle `https://raw.githubusercontent.com/ghostery/adblocker/master/packages/adblocker/assets/ublock-origin/resources.json` (`{scriptlets:[{name,aliases,body,dependencies,executionWorld?,requiresTrust?}], redirects:[{name,aliases,contentType,body}]}`) and converts it: `*.fn` names become `fn/javascript`, `requiresTrust` scriptlets need permission bit 1 (granted only to the uBO lists), `executionWorld: ISOLATED` scriptlets are dropped (execute_java_script runs in the main world), `;base64` content types keep their body as-is.
- Filter list URLs: `https://easylist.to/easylist/easylist.txt`, `https://easylist.to/easylist/easyprivacy.txt`, `https://ublockorigin.github.io/uAssets/filters/{filters,badware,privacy,quick-fixes,unbreak}.min.txt` (the `.min` builds have no `!#include`), `https://pgl.yoyo.org/adservers/serverlist.php?hostformat=adblockplus&showintro=1&mimetype=plaintext`.
- `$redirect` matches are cancelled, not redirected (CEF cannot serve the redirect body from `on_before_resource_load` without a resource handler).
- cef-rs trap: `CefStringList::clone()` of a callback-provided list yields an empty list (the clone becomes `Borrowed`, whose `into_iter` reads nothing). Iterate with `std::mem::take(list).into_iter()`.
- `execute_java_script` from `on_load_start` runs in the new document (verified: the login script's window symbol is present after load), so load-start injection works for cosmetic CSS and the login detector.
- `Browser::load_url("javascript:...")` executes in the current page (used only by the scratchpad harness).
- `download_image` handles SVG favicons (GitHub's) and `.ico`; `Image::as_png` needs non-null width/height out params.
- - `do_close` must not return 0 for a browser embedded in the shell's window: CEF then calls `performClose:` on the host NSWindow and the browser never reaches `on_before_close`. Mini removes the browser NSView from its superview and returns 1, which destroys just that browser.
- Ad-hoc signing traps cookie encryption: Chromium reads the "Chromium Safe Storage" login-keychain item at startup, and its ACL trusts each ad-hoc build by cdhash. Any code change gives a new cdhash, so the next launch raises a SecurityAgent "Always Allow" prompt; until it is answered the cookie store never loads and every navigation stalls before reaching the network (blank page, stop button, no load_start). bundle.sh therefore signs with a stable certificate identity by default, whose keychain grant survives rebuilds. With ad-hoc signing, answer the prompt. `--use-mock-keychain` confirms the diagnosis but re-encrypts cookies with a fixed key, so never run it against the real profile. Identical sources rebuild to the same cdhash.
- Two browser processes sharing one `root_cache_path` collide (`bootstrap_check_in ... Permission denied`) and the second hangs in `cef_shutdown` until "Teardown watchdog expired". Kill stale instances before relaunching.
- Renderer-initiated `window.open` to a `data:` URL is blocked by Chromium even after `on_before_popup` allows it; test popups with real URLs.
- Swift 6: the CrApp/CefApp protocols are declared `@MainActor @objc(Name)` so the main-actor NSApplication subclass can conform. C callbacks convert strings to `String` before `MainActor.assumeIsolated`, and pass pointers across it as `UInt` bit patterns (raw pointers are not Sendable).
- Every `mini_browser_*` call for a tab whose browser does not exist (lazy tab, or after `browser_closed`) panics in Rust. The shell gates on `Tab.browserState == .created`; a popup tab is `.pendingPopup` until the `popup_requested` callback has returned (promoted on the next main-queue turn).
- Tab ids are never reused: once `browser_closed` fires for an id, Rust rejects further calls, so a reset pinned tab gets a new Tab object and id.
- Hidden menu items need `allowsKeyEquivalentWhenHidden = true` to keep their shortcut (used for Cmd-+ and Opt-Cmd-Up/Down).
- The sidebar NSHostingView must have `sizingOptions = []`, or SwiftUI's fitting size fights the split view and the sidebar renders offset and clipped.
- `webAreaView` is positioned by explicit constraints, never by NSBackgroundExtensionView's automatic placement: top = `window.contentLayoutGuide` top (below titlebar and toolbar), leading = the content view's `safeAreaLayoutGuide` (sidebar overlap). Automatic placement let the CEF view slide under the toolbar and hide the traffic lights, and did not follow sidebar toggles.
- NSBackgroundExtensionView's internal `_NSCoreHostingView<BackgroundExtensionContainer>` sits above its content view and swallows every click; `PassthroughBackgroundExtensionView` overrides `hitTest` to route into the content view.
- An NSHostingView whose content can be empty (command bar suggestions) must drop `.maxSize` from `sizingOptions`, or its required max-width constraint collapses fixed-width containers.
- Overlays live in the content item's view (`rootView`), never in the NSSplitView itself (its subviews are panes).
- zsh here has `noclobber`: overwrite files with `>|` or an editor, not `>`.
- `swift build` in this toolchain uses the swiftbuild backend: products live in `shell/.build/out/Products/<Config>/`, so `bundle.sh` asks `swift build --show-bin-path` instead of assuming `.build/<config>/`.

## Verification

- `make run` builds, bundles, signs and launches. Gates: app launches, page renders in the content card, tabs create/switch/close/nest, Cmd shortcuts work while a page has focus, Cmd-Q quits cleanly (no crash report), session restores on relaunch.
- `cargo clippy` in `core/`, `swift build` in `shell/`.

## Status

Phase 1: skeleton (window, sidebar, embedded Chromium, tab tree, command bar, session restore).
