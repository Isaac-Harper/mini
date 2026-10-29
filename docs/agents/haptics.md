# Haptic map

`Haptics.swift` is the only caller of `NSHapticFeedbackManager` (mice get nothing automatically). Every moment is a named `Haptics` method; `HapticGate` admits at most one haptic per 90 ms and none while the current event is a momentum-phase scroll. Only direct-manipulation code paths call them, never undo/redo, menu or keyboard commands, restore or animations (verified: Cmd-Z, Shift-Cmd-Z, Ctrl-Shift-Down, Ctrl-1/2, Hide/Show Sidebar and split toggles record nothing).

`Haptics.swift` also holds the pure detent rules (`HapticGate`, `ThresholdCrossing`, `DetentEntry`, `DetentChange`, `TabDragDetent`, `SidebarWidthEdge`, `SplitDividerDetent`, `TabPlacement`). The split divider's magnetic center snap lives here too.

| Moment | Method | Pattern / time | Trigger |
| --- | --- | --- | --- |
| Sidebar divider snaps collapsed or expanded | `sidebarSnappedCollapsed` | levelChange / now | `MainWindowController.noteSidebarResize`: `didResizeSubviews` carrying `NSSplitViewDividerIndex` while the current event is a left-mouse drag or up; `DetentChange<Bool>` on `isCollapsed` |
| Sidebar reaches min (200) or max (400) width | `sidebarReachedWidthLimit` | alignment / drawCompleted | same notification, `SidebarWidthEdge` through `DetentEntry` (fires on arriving, not while staying); the hosting view is laid out first because its frame lags the pane during a drag |
| Split divider snaps to the center | `splitSnappedToCenter` | alignment / drawCompleted | `WebAreaView.dragDivider`: `SplitDividerDetent.snappedLeadingWidth` pulls the leading width to exactly half within 8pt |
| Split divider hits the 320pt minimum on either side | `splitReachedMinimum` | alignment / drawCompleted | same, `DetentEntry<SplitDividerDetent>` reset when the drag ends |
| Tab drag target changes kind | `tabDragTargetChanged` | alignment / drawCompleted | `SidebarDragModel.target` / `isPastTearOff` didSet: `TabDragDetent` (reorder or nest per saved/regular section, pinned area, tear-off) through `DetentChange`: nil gaps between drop targets are ignored, the first target of a drag is silent, the same detent never repeats; moving between reorder slots in one section is silent |
| Peek sidebar slides open | `peekSidebarOpened` | alignment / drawCompleted | `PeekSidebarController.peek` |
| Completed drop changed kind or nesting | `tabDropChangedPlacement` | levelChange / drawCompleted | `SidebarDragModel.drop` compares `TabPlacement` (pinned/saved/regular plus parent id) before and after the drop delegates' action |
| Page swipe crosses its commit point | `swipeNavigationCrossedThreshold` | levelChange / drawCompleted | `SwipeNavigationController`, `ThresholdCrossing` per gesture: fires at progress 1, rearms only below 0.9 |
| Space swipe crosses 35% of the width | `spaceSwipeCrossedThreshold` | levelChange / drawCompleted | `SpaceSwipeController`, same `ThresholdCrossing` on `abs(offset) / (0.35 * width)`, only toward a real neighbor |
| Tab becomes a little window | `tabTornOff` | levelChange / drawCompleted | `ShellController.tearOff` (not the undo/redo transfer) |
| Little window docks into the sidebar | `littleWindowDocked` | levelChange / drawCompleted | `ShellController.dock` (not the undo/redo transfer) |
