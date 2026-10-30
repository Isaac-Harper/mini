# Haptic map

`Haptics.swift` is the only caller of `NSHapticFeedbackManager` (mice get nothing automatically). Every moment is a named `Haptics` method; `HapticGate` admits at most one haptic per 90 ms and none while the current event is a momentum-phase scroll. Only direct-manipulation code paths call them, never undo/redo, menu or keyboard commands, restore or animations (verified: Cmd-Z, Shift-Cmd-Z, Ctrl-Shift-Down, Ctrl-1/2, Hide/Show Sidebar and split toggles record nothing).

Controls use a small semantic vocabulary on top of the same gate: `ControlFeedback.press` (generic), `.toggle` (levelChange) and `.snap` (alignment), all at `.now`. `Haptics.controlActivated(_:)` fires only when the current event is a `leftMouseUp`, so it runs on the click that commits (mouse up inside), never on mouse down, and stays silent for keyboard shortcuts, menu items and programmatic calls. SwiftUI buttons take `.hapticFeedback(_:)` (a simultaneous tap gesture on the button itself, so a parent row never fires for a child button); tap-gesture rows call `Haptics.controlActivated` in their tap handler; AppKit buttons are `HoverHighlightButton`s, whose `sendAction` override fires their `feedback` (the little window's toolbar actions call it directly). Nothing fires on hover.

| Control | Feedback | Where |
| --- | --- | --- |
| Sidebar toggle (toolbar and collapsed cluster) | toggle | `HoverHighlightButton.feedback = .toggle` in `WindowToolbar.item` and `WindowControlsCluster.button` |
| Back, forward (toolbar and cluster) | press | `HistoryButton` (a `HoverHighlightButton`) on mouse up inside, not the long-press menu |
| Address pill reload/stop, Fill Password key | press | `.hapticFeedback(.press)` |
| Space buttons | toggle | `SpaceBarIconButton(feedback: .toggle)` |
| New Space, New Tab | press | `SpaceBarIconButton`, `SidebarActionRow` |
| Pinned tiles, tab rows and split halves (including Shift- and Cmd-clicks for multi-select) | press | tap handlers |
| Row close buttons | press | `.hapticFeedback(.press)` |
| Mute toggle on rows and tiles | toggle | `AudioToggleButton` |
| Now Playing play/pause | toggle | `.hapticFeedback(.toggle)` |
| Now Playing row (reveal), weather row, downloads row | press | tap handler, `.hapticFeedback(.press)` |
| Little window back, forward, Open in Mini | press | `LittleWindowController` toolbar actions |
| Command bar rows (every kind except disabled actions and the hint) | press | `CommandSuggestionsView` tap handler; Return and arrows stay silent |

Context menu items, multi-select group actions chosen from the menu, Cmd-W, Delete, Ctrl-1/2 and the sidebar keyboard stay silent. The toolbar sidebar toggle's click also reaches `sidebarSnappedCollapsed` (the collapse happens inside a `leftMouseUp`), which the 90 ms gate drops, so one click still gives one haptic. Verified with posted (queued) mouse and key events: one admitted haptic per row, space button, New Tab and toolbar toggle click; two clicks 12 ms apart admit one and drop one; Down/Return in the focused sidebar, Ctrl-1, Cmd-Ctrl-S, pointer movement over rows and programmatic selection or back record nothing. Now Playing has no skip control, so there is no skip haptic.

`Haptics.swift` also holds the pure detent rules (`HapticGate`, `ThresholdCrossing`, `DetentEntry`, `DetentChange`, `TabDragDetent`, `SidebarWidthEdge`, `SplitDividerDetent`, `TabPlacement`). The split divider's magnetic center snap lives here too; the page width detent table and snap are `PageWidth` in `Sources/MiniRules` (unit tested).

| Moment | Method | Pattern / time | Trigger |
| --- | --- | --- | --- |
| Sidebar divider snaps collapsed or expanded | `sidebarSnappedCollapsed` | levelChange / now | `MainWindowController.noteSidebarResize`: `didResizeSubviews` carrying `NSSplitViewDividerIndex` while the current event is a left-mouse drag or up; `DetentChange<Bool>` on `isCollapsed` |
| Sidebar reaches min (200) or max (400) width | `sidebarReachedWidthLimit` | alignment / drawCompleted | same notification, `SidebarWidthEdge` through `DetentEntry` (fires on arriving, not while staying, so a drag that starts at a limit is silent); the hosting view is laid out first because its frame lags the pane during a drag. Expanding from collapsed first restores the old width and then clamps to the minimum within the same mouse event, so an edge reached on the event that snapped (`sidebarSnapEvent`) belongs to the snap and stays silent |
| Split divider snaps to the center | `splitSnappedToCenter` | alignment / drawCompleted | `WebAreaView.dragDivider`: `SplitDividerDetent.snappedLeadingWidth` pulls the leading width to exactly half within 8pt |
| Split divider hits the 320pt minimum on either side | `splitReachedMinimum` | alignment / drawCompleted | same, `DetentEntry<SplitDividerDetent>` reset when the drag ends |
| Tab drag target changes kind | `tabDragTargetChanged` | alignment / drawCompleted | `SidebarDragModel.target` / `isPastTearOff` didSet: `TabDragDetent` (reorder or nest per saved/regular section, pinned area, tear-off) through `DetentChange`: nil gaps between drop targets are ignored, the first target of a drag is silent, the same detent never repeats; moving between reorder slots in one section is silent |
| Page edge drag reaches 375, 768, 1024 or 1280 | `pageWidthReachedDetent` | alignment / drawCompleted | `PageWidthDrag.drag`: `PageWidth.dragged` snaps the width to a detent narrower than the full width within 6pt, `DetentEntry<Double>` on `PageWidth.detent(at:)`, seeded at mouse down with the tab's current width so a drag that starts on a detent is silent; double-click restore and tab switches record nothing |
| Peek sidebar slides open | `peekSidebarOpened` | alignment / drawCompleted | `PeekSidebarController.peek` |
| Completed drop changed kind or nesting | `tabDropChangedPlacement` | levelChange / drawCompleted | `SidebarDragModel.drop` compares `TabPlacement` (pinned/saved/regular plus parent id) before and after the drop delegates' action |
| Page swipe crosses its commit point | `swipeNavigationCrossedThreshold` | levelChange / drawCompleted | `SwipeNavigationController`, `ThresholdCrossing` per gesture: fires at progress 1, rearms only below 0.9 |
| Space swipe crosses 35% of the width | `spaceSwipeCrossedThreshold` | levelChange / drawCompleted | `SpaceSwipeController`, same `ThresholdCrossing` on `abs(offset) / (0.35 * width)`, only toward a real neighbor |
| Tab becomes a little window | `tabTornOff` | levelChange / drawCompleted | `ShellController.tearOff` (not the undo/redo transfer) |
| Little window docks into the sidebar | `littleWindowDocked` | levelChange / drawCompleted | `ShellController.dock` (not the undo/redo transfer) |
