# Testing and the background harness

How Mini gets verified without disturbing the installed app, and the traps found while doing it. The scenario harness itself lives outside the repo (a scratch directory); its debug hooks are injected for a run and never committed.

## Gates

- `make run` builds, bundles, signs and launches. Gates: app launches, page renders in the content card, tabs create/switch/close/nest, Cmd shortcuts work while a page has focus, Cmd-Q quits cleanly (no crash report), session restores on relaunch.
- `cargo clippy` and `cargo test` in `core/` (unit tests cover the pure rules and the injected script builders), `swift build` in `shell/`.
- `make test` runs `cargo test` and the Swift tests. Swift tests cover only the `MiniRules` target: `swift test` alone links the app with `-rdynamic`, which keeps the CEF sandbox symbols `-dead_strip` normally drops and fails, so the Makefile builds just `MiniRulesTests` and runs `swift test --skip-build`.
- Visible changes come with screenshots of the real app.

## Rules for test instances

- Never touch the real profile, session or UserDefaults, and never quit the installed Mini the user is running. A test build gets its own bundle id (`dev.isaacharper.mini.scratch`, so its own UserDefaults domain), is re-signed after the plist change, and points at a scratch support directory through `MINI_SUPPORT_DIRECTORY`; the debug hook refuses to start without both.
- Launch test instances with `--use-mock-keychain` (scratch profile only, see signing-release-codecs.md).
- Background only: accessory activation policy, windows ordered back, `open -g`, never activate or bring a window to the front, no System Events keystrokes or clicks. Capture with ScreenCaptureKit window capture by window number.
- Block fronting at the runtime, not per call site: the harness's background hook exchanges `NSApplication.activate`, `activateIgnoringOtherApps:` and `NSWindow.makeKeyAndOrderFront:`, `orderFront:`, `orderFrontRegardless` for versions that order the window back (and `makeKey`) and log each blocked call, and the run script compares the frontmost app before and after. Hooks on single call sites missed `openLittleWindow`, so a scenario opening a link through `openExternalURL` fronted its little window and activated the app. The app itself keeps activating there: a link opened from another app brings the browser forward, as Safari and Chrome do.
- Use local demo pages only, and never log page content, notification text or login values.
- Two browser processes sharing one `root_cache_path` collide (`bootstrap_check_in ... Permission denied`) and the second hangs in `cef_shutdown` until "Teardown watchdog expired". Make sure the previous test instance has exited before launching the next.

## Background instance facts

- A background test instance (accessory activation policy, window ordered back, never active) never gets key status, even after `makeKey()`, and Chromium then ignores key equivalents sent to the page view, so the page side of Cmd-Z routing can only be driven by calling `pageUndoKeyPressed` directly; menu key equivalents (`NSApp.mainMenu.performKeyEquivalent`) still work.
- Hover zones (the peek sidebar's left edge, the collapsed controls corner) use `.activeInActiveApp` tracking areas, which AppKit never fires in an inactive instance, so a pointer at the edge does nothing there. Every collapse path (Cmd-Ctrl-S through the menu, the View menu item, the toggle action) enables peek through `didResizeSubviewsNotification` and `updateCollapsedControls`; the harness collapses through the menu key equivalent and then calls the edge `HoverZoneView`'s `mouseEntered` with an enter event, never `PeekSidebarController.setEnabled` by hand.
- Launch such instances with `--disable-backgrounding-occluded-windows --disable-renderer-backgrounding --disable-background-timer-throttling` so covered windows keep painting, and capture them with ScreenCaptureKit window capture.
- Separate windows (the tear-off preview panel, little windows) are captured by their own window numbers; a capture of the main window does not include them.
- The sidebar split pane is 8pt wider than `sidebarHostingView` (the floating glass inset), so a scripted divider drag must start at the split view's first arranged subview `maxX`, not at the hosting view's width. A `mouseDown` off the divider returns at once, and the drag events already queued for it then land in the next drag, which looks like a first drag that does not track.
- Shots requested from a scenario step are taken by a poller, so a scenario that wants a mid-gesture frame must pause after asking for it (the space swipe and tear-off scenarios hold the gesture for over a second); otherwise the capture shows the state after the gesture finished.
- A seeded session.json carries `lastSelectedAt` timestamps. Once they are more than 12 h old, launch archives every unselected regular tab when Close the Day is off, and with it on (the default) a seed without a `closedDay` of today folds them into a day group at launch; so scenarios that look tabs up by title fail with a missing tab. Stamp seeds with the current time (seconds since 2001-01-01) and delete archive.json before each fresh run.

## Driving the app without input devices

- `Browser::load_url("javascript:...")` executes in the current page with user activation; the harness uses it to drive page state (play media, set titles, request fullscreen).
- Synthesized `rightMouseDown`/`rightMouseUp` NSEvents sent with `NSApp.sendEvent` at a point over the CEF view reach Chromium and produce `run_context_menu`, which is how context menus are driven without System Events.
- Scroll NSEvents made from a `CGEvent` (`NSEvent(cgEvent:)` with scroll phases) have no window, even after `postToPid` to Mini itself, so the harness feeds them through a hook that maps their screen location; the page never receives them, and page-side scroll room is tested with DOM `WheelEvent`s instead. Synthesized events carry timestamp 0, which is why swipe velocity is timed at receipt.
- `chrome://crash` loaded with `load_url` crashes the renderer and fires `on_render_process_terminated` (used to test the crash overlay).
- Renderer-initiated `window.open` to a `data:` URL is blocked by Chromium; test popups with real URLs.
- While the print panel is up only common-mode run loop sources fire, so `DispatchQueue.main.asyncAfter` steps wait until it closes; `NSApp.abortModal()` cancels it.

- Close the Day takes its time as a `now:` argument (`closeTheDayIfNeeded(now:)`, `archiveIdleTabs(now:)`), so the harness drives day boundaries, the 4 am rule and group expiry with fake dates; seed `closedDay` with today's logical midnight to keep launch from folding.

## Shell

- zsh here has `noclobber`: overwrite files with `>|` or an editor, not `>`.
