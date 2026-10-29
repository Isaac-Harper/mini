# Spaces, session and history

Detail for spaces (profiles, colors, swipe), session.json and per-space history. AGENTS.md has the one-line summaries.

## Spaces

- `ShellController.spaces` holds `Space` objects (id, name, SF Symbol, color, `usesDefaultProfile`, its own `TabStore`); `store` is always `currentSpace.store`. Tab ids come from one shared `TabIdentifierMint`, so ids are unique across spaces and callbacks find a tab's space with `space(containing:)`.
- Each space maps to a CEF request context registered in Rust with `mini_space_create` before any of its browsers exist; the default-profile space uses the global context (`Profile/Default`), the rest `Profile/Spaces/<id>`. Popups inherit their opener's request context, so they stay in the opener's space.
- Only the current space's store drives the window: `tabStore(didSelect:)` and `tabStoreDidChangeSplits` ignore other stores, and `switchToSpace` hides the old space's shown tabs and shows the new one's through `refreshDisplayedTabs`. Background spaces keep their browsers running (title, audio, downloads, notifications still arrive; a docked Player in another space leaves the slot panel, stays hidden in the web area and keeps playing, and docks again when its space is current); `reveal(_:)` switches space before selecting (Now Playing, notification clicks).
- The default-profile space is never deletable (it holds the user's original cookies and logins), and the last space can't be deleted either. Deleting a space closes its tabs and little windows, waits for those browsers' `browser_closed`, then calls `mini_space_destroy` and removes `Profile/Spaces/<id>`; launch also sweeps `Profile/Spaces` for folders of spaces that no longer exist. Nothing outside `Profile/Spaces` is ever deleted.
- `Spaces.swift`: `Space` (observable), the symbol list for new spaces, cache directory paths, and `TabIdentifierMint`.
- `ShellSpaces.swift`: ShellController extension for spaces: engine registration and orphan sweep, `switchToSpace` (closes overlays, fades the web area in from 30% opacity over 0.2s; the sidebar list crossfades by `.id(currentSpace.id)`), create, rename, delete with the native confirmation sheet, and the New/Rename sheets (NSAlert with a symbol popup and name field). Ctrl-1 to Ctrl-9 switch spaces.

## Space colors

- `SpaceColors.swift`: `SpaceColor`, the 8-tint palette (amber, blue, green, teal, purple, pink, red, graphite) as dynamic sRGB `NSColor`s with separate light and dark values, `nextUnused`, and menu swatches.
- The current space's color is the sidebar's SwiftUI `.tint` (selected row `SelectionHighlight`, focus ring, drop indicators, selected pinned tile glass, the current space button in its own color) and `WebAreaView.spaceAccent` (loading progress line, split focus border), set by `applySpaceAccent` at launch, on switch and on change.
- Space > Space Color and the space button's context menu (a menu `Picker`) set it; not undoable (no tab change).
- The sidebar background tint (space color plus the page's theme color) is `SiteTintView`, in shell-ui.md.

## Space swipe

- `SpaceSwipe.swift`: two-finger swipe between spaces on the main sidebar. `SpaceSwipeController` is a local `.scrollWheel` monitor (phase-based precise scrolls that begin over `sidebarHostingView`, only with `NSEvent.isSwipeTrackingFromScrollEventsEnabled`, more than one space, sidebar visible, no sheet, not while a previous swipe settles).
- Pure `SpaceSwipeTravel` rules: the axis locks once travel reaches 6pt (horizontal when |dx| > |dy|), vertical gestures are never touched; past the lock every event and the momentum are consumed.
- `SpaceSwipeModel` (`ShellController.spaceSwipe`: offset, neighbor, edge, width) drives `SpaceSwipeStage`, which draws the current space's `SpaceTabsView` at the offset and the neighbor's beside it (non-hit-testable), clipped; Reduce Motion crossfades instead. The neighbor's `SpaceTabsView` sets `.tint` to the neighbor's own color, so its selected row and accents never show in the outgoing space's color (they did before; the selection flipped color at commit).
- Fingers left go to the next space; no neighbor rubber-bands (`(1 - 1/(x*0.55/w + 1)) * w`). Release commits at 35% of the width or 600pt/s toward the neighbor (velocity from the last 0.1s of samples timed at receipt, since synthesized events carry timestamp 0), springs the neighbor into place, then switches space with animations disabled; otherwise it springs back.
- The sidebar background tint crossfades from the current to the neighbor color by progress (`SiteTintView` animates only on color changes so tracking stays 1:1). The page area does not move during the swipe: it keeps showing the current space's page until the switch commits.
- Page swipes (SwipeNavigationController) only start over the selected host view, so the two never overlap.

## session.json

- Shape: `{spaces: [{id, name, symbol, color, usesDefaultProfile, contents: {tabs, selectedPath, pinnedTabs, selectedPinnedIndex, splits, player, selectsPlayer}}], currentSpace, closedDay}`. `player` (pinnedURL, url, title) and `selectsPlayer` are optional; the Player restores lazy and idle (its dock phase is never saved). Folded regular roots also carry `foldedDay` and `foldedAt` (tabs-and-undo.md, Close the Day); both and `closedDay` are optional, so older files load (no folds, and the first launch closes the day). `tabs` holds saved roots first, then regular roots; every tab carries `kind` (`saved` or `regular`), saved ones also `savedURL` and `savedTitle`.
- A file without `kind` loads every tab as regular, and the next save writes `kind` everywhere. A space without `color` (older files) gets the next unused palette color in order at load (so Personal amber, Work blue).
- A file in the pre-spaces shape (top-level `tabs`) is migrated once at load into Personal (person.fill, default profile) plus an empty Work (briefcase.fill), and launch immediately saves the new shape; the old shape is never written.
- `SessionStore.swift`: session.json encode/restore and debounced saves; splits are saved as tree index paths plus fraction (`splits`); `pinnedTabs`, `selectedPinnedIndex`, `splits` and per-tab `lastSelectedAt` are optional so older files still load (a tab without `lastSelectedAt` counts as just selected).
- Launch closes the day if a new one started, then runs the archive pass; with Close the Day off, restored unselected regular tabs whose `lastSelectedAt` is more than 12 h old are archived at once (this is what empties stale test seeds; see testing-harness.md).

## History

- `HistoryStore.swift`: browsing history in SQLite (system `SQLite3`, WAL), one database per space at `History/<space id>.sqlite`, table `visits(url PRIMARY KEY, title, last_visit, visit_count)`. `HistoryLibrary` opens stores lazily, records only http(s) URLs (`address_changed` counts a visit, `title_changed` updates the title; main-window and little-window tabs both record into their space), removes a deleted space's files when its deletion finishes and sweeps files of unknown spaces at launch. `Frecency.score` = visit count times a recency weight (100 under 4 days, 70 under 14, 50 under 31, 30 under 90, else 10). Database errors are logged without content and never crash.
- `ShellHistory.swift`, `HistoryWindowController.swift`: History menu (its `NSMenuDelegate.menuNeedsUpdate` inserts the current space's 15 most recent pages, tagged 7701, between Back/Forward and Show All History; picking one loads it in the current tab), Show All History (Cmd-Y: a SwiftUI window with a search field over the current space's history, newest first, double-click opens in a new tab, hover x or context menu deletes a row, reloads on key, on space switch and on every record), Clear History... (confirmation sheet, deletes the current space's rows). Cmd-W closes the history window when it is key. The command bar shows up to 4 frecency-ranked "History" rows after open tabs (pages already open are skipped); they open like a typed URL.
