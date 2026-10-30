# Command bar states

Every state the command bar can be in, what it shows, what the keyboard and mouse do, and what was wrong before the October 2026 audit. Code: `CommandBarController.swift` (field, keys, focus, height), `CommandBarModel.swift` (rows and selection), `CommandSuggestionsView.swift` (rows), and the pure rules in `Sources/MiniRules`: `AddressInput` (URL or search), `CommandResults` (ranking, dedupe, caps, late suggestions), `CommandSelection` (selection retention, arrows, pointer, Escape, the modifier matrix), `InlineCompletion`. All unit tested.

## Decisions

- Escape: reverts the field to what it opened with (empty for Cmd-T, the page address for Cmd-L), then a second Escape closes. One Escape closes when nothing was typed. Never runs mid-composition (the input method owns Escape then).
- Modifier matrix (`CommandOpenTarget`, the same for Return and a click):

  | Entry | Return | Cmd-Return | Option-Return |
  | --- | --- | --- | --- |
  | Cmd-T (New Tab) | new tab, selected | background tab | child of the current tab |
  | Option-Cmd-T (New Child Tab) | child tab, selected | background tab | child of the current tab |
  | Cmd-L (Open Location) | current tab navigates | background tab | child of the current tab |

  Cmd wins over Option; Shift is ignored. Switch to Tab rows always switch, Archived rows always reopen as a new tab in their space, action rows always run. Pasted links: Return opens them, Cmd-Return in the background, Option-Return nested under the first. A child of a pinned tab or the Player opens as a root tab.
- Arrows do not wrap: Down stops at the last row, Up stops at the first row (or returns to no highlight in the empty state and Cmd-L). Rows that cannot be selected (the hint, "No Matching Actions") are skipped.
- Inline completion (Safari style): after 2 typed characters, when typing forward with the caret at the end, the first open tab host (most recently selected first) or history host (frecency) that starts with the typed text is filled in and selected. Typing through it keeps completing, Backspace drops it and does not re-complete until the next forward keystroke, Tab or Right accepts it. Never for text with spaces, `/`, `:`, `?`, `#` or a leading `>`, never mid-text, never during composition.
- Tab: accepts the inline completion if one is showing, else moves down; Shift-Tab moves up.
- Query memory: none. Every open starts fresh: Cmd-T empty, Cmd-L the page address selected, no pasted links, no completion, no suggestions, scrolled to top, the pointer anchor reset.
- Cmd-1 to Cmd-9 stay Select Tab N (the menu); selecting a tab closes the bar. No per-row number shortcuts.
- Cmd-Delete (and Cmd-Forward-Delete) on a highlighted tab, history or archived row closes the tab (undoable), deletes the history entry or removes the archive entry, keeping the highlight at the same position. On the top row while typing it edits the field as usual.

## Layout rules

- Rows have fixed heights (row 36, section header 28, hint 32, pasted preview 24, all scaled), so `CommandSuggestionsView.contentHeight(of:)` computes the list height synchronously; the height constraint is set from it and animated (0.18s ease-out, instant with Reduce Motion). The list is a top-aligned SwiftUI `ScrollView`, so a growing or shrinking height clips at the bottom and never pushes rows over the field.
- Height is capped to the web area: 84% of its height minus the field and a 24pt margin (at least two rows); longer lists scroll, and keyboard moves scroll the highlighted row into view. Resizing the window refits.
- Width: 760 x Interface Size, at most the web area minus 32 and the window minus 80. The width constraint is created once (it used to be re-added on every open, and the old 760 constraint won after a size change).
- Typed order: the open/search row, Switch to Tab, Local Servers, History, Archived, then Search Suggestions last. Caps: tabs 4, servers 3, history 4, archived 3, those four together 6, suggestions 3, so at most 10 rows. Empty state: recent tabs 4, Frequently Visited 3, Local Servers 3 (together 8), then the hint.
- Dedupe by address key (`CommandResults.key(forAddress:)`: scheme family http/https, host without `www.`, port, path without a trailing slash, query; fragment dropped). An address never shows twice; history, archived and server rows for any open tab (including the current one) are hidden; when the typed address is an open tab, that tab's Switch to Tab row replaces the open row.
- Section headers: Local Servers, History, Archived, Search Suggestions (typed); Frequently Visited, Local Servers (empty). Tabs and the top row have none.

## State matrix

| State | Shows | Keyboard | Mouse | Before |
| --- | --- | --- | --- | --- |
| Cmd-T | Empty field, placeholder "Search or enter address", empty-state rows, no highlight | Typing searches; Down highlights the first row | Hover highlights after the pointer moves; click opens | Highlight on the first recent tab, so Return switched tabs |
| Option-Cmd-T | Same as Cmd-T | Return opens a child of the current tab | Same | Same |
| Cmd-L | Page address, fully selected; empty-state rows, no highlight | Return re-opens the address in the current tab; typing replaces it | Same | No rows at all |
| Address pill click | Inline pill editor in the sidebar (not the bar); with no page, the bar in Cmd-L mode | Return navigates, Escape restores | Click outside ends editing | Unchanged |
| Little window Cmd-L | The little window's own address field, selected | Return navigates the little window, Escape restores the address | | Unchanged |
| Open with a sheet attached | Nothing (open is refused) | | | Opened behind the sheet |
| Open during page fullscreen | Fullscreen ends first, then the bar opens | | | Bar over the fullscreen page |
| Open while a little window is key | Main window is made key, then the bar opens | | | Field became first responder of a non-key window, typing went to the little window |
| Zero tabs in the space | Local servers (if any) and the hint, never blank | Return on empty closes | | Blank when no local servers listened |
| First open after launch | Rows grow in from the top as local servers arrive | | | At about 1.2s the late local server scan grew the content inside a shorter hosting view, which centered it over the field |
| Empty query | Recent tabs, Frequently Visited, Local Servers, "Type > for actions" | Return closes; Up from the first row returns to no highlight | | Recent tabs and servers, Return switched to the first tab |
| Address-like input (`example.com`, `github.com/apple`) | Open row with globe, https | Return opens per the matrix | | Same |
| Search input (words, spaces) | Search row "Search Google" | Return searches | | Same |
| Bare host with port, `localhost`, `*.localhost` | Open row, http | | | `*.localhost` and IPv6 went to https |
| `:3000` / bare `3000` | `:3000` opens http://localhost:3000; bare `3000` only while a server listens there, else searches | | | Same |
| Decimal or number (`3.14`, `12345`) | Search row | | | `3.14` opened https://3.14 |
| IPv4 (`192.168.1.1`) | Open row, http | | | https, failing on routers |
| Very long input | One search row, single-line field scrolls; no suggestion fetch over 200 characters | | | Fetched suggestions for any length |
| IME composition | Rows frozen at the pre-composition state | Return, Escape, arrows go to the input method; nothing selects or runs | | Rows rebuilt on every marked-text change |
| Inline completion | Typed text plus selected completion; top row opens the completed host (or switches to its open tab) | See Decisions | | Did not exist |
| Paste one URL | Like typing it | | | Same |
| Paste 2+ URLs | "N links pasted", one "Open N Links" row with up to 6 previews plus "+N more" | Return, Cmd-Return, Option-Return per the matrix; Escape reverts to empty | | Same |
| Typed results | Top row, then sections in the order above, headers, at most 10 rows | Highlight stays on the same row id while it exists, else the top row | | Search suggestions were second, so late arrivals pushed every row down; history duplicated tabs past the cap and the current page |
| Late search suggestions | Appended as the last section; stale ones that still match the new text stay until replaced | Highlight kept; if the highlighted suggestion vanishes, the top row | Rows under the pointer never move | Suggestions inserted at row 2 reordered rows under the pointer and the keyboard highlight |
| Suggestion fetch fails or offline | Nothing (no error rows) | | | Same |
| Slow history | SQLite search with a 60-row limit, measured 0.03 ms on the seeded profile; synchronous | | | Same |
| No results | Only the open/search row, so Return always opens or searches | | | Same |
| `>` empty | Actions, recently run first, at most 10, first enabled one highlighted | | | First row highlighted even when disabled |
| `>` no matches | "No Matching Actions" (not selectable) | Return does nothing, bar stays | | Empty list and a blank bar |
| Disabled action | Dimmed, "Dimmed" for VoiceOver | Return does nothing | Click does nothing, no haptic | Same, but a click on it played no haptic only by accident |
| Backspace out of `>` | Back to the empty state or typed results | | | Same |
| Up/Down | | No wrap, skips the hint | | Clamped, but could land on nothing |
| Escape | | Revert, then close (see Decisions) | | Always closed |
| Cmd-Delete on a row | | See Decisions | | Deleted the field text only |
| Delete, Left/Right, Home/End in the field | | Normal text editing; Up/Down always move the highlight | | Same |
| Hover vs keyboard | | | The pointer takes the highlight only after it moves (`CommandSelection.pointerTakesSelection` against an anchor reset on open); rows scrolling or reflowing under a resting pointer never steal it | Any row that appeared under the resting pointer took the highlight |
| Click a row | | | Opens per the matrix with the click's modifiers; plays `press` | Only action rows played `press` |
| Click outside | Bar closes | | Focus returns as on Escape | Same, but focus always went to the page |
| Long lists | Scroll inside the capped height | Highlight scrolls into view | Wheel scrolls; the highlight does not follow | List could grow past the window bottom |
| Close (Escape, click outside, Cmd-W) | | Focus returns to the sidebar row if the bar was opened from sidebar keyboard focus, else the page | | Always the page |
| Cancelled Cmd-L | Page address untouched | | | Same |
| Next open | Fresh (see Decisions) | | | Same |
| Interface Size 85% to 125% | All metrics and the 760 width scale | | | Width never scaled |
| Small window | Width shrinks to the web area minus 32, height caps and scrolls | | | Height unbounded |
| Multiple windows | Bar lives in the main window only; little windows use their own field | | | |
| Space switch | Bar closes | | | Same |
| Dark and light | System colors on glass with a 72% window-background backing | | | Same |
| Reduce Motion | No spring, blur or height animation, highlight does not glide | | | Same |
| Reduce Transparency | Backing fully opaque | | | 72% backing |
| Increase Contrast | 1pt separator border, stronger highlight fill, 3pt focus ring | | | Focus ring only |
| VoiceOver | Field labelled "Command Bar"; rows are single buttons labelled "title, detail, hint" with the selected trait; headers are headers | Arrow moves announce the highlighted row | | Rows read as separate text fragments, nothing announced |
| Haptics | | Keyboard silent | Row clicks play `press` (E14) | |

## Verification

The background harness (testing-harness.md) drives every row above that can run in a background instance through the controller's own delegate methods, field editor `insertText`/`setMarkedText`, and menu key equivalents, and logs one PASS/FAIL line per state. Not covered by the harness: page fullscreen entry, a key little window, real pointer hover and click delivery (and so the click haptic), Reduce Transparency and Increase Contrast at runtime, the VoiceOver announcement reaching speech, an offline fetch.
