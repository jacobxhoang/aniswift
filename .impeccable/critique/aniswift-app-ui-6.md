# Aniswift app UI, design critique pass 6

Method: design review only (detector not applicable, native platform). Same method as passes 1 to 5; the
skills' databases and the critique-storage helpers cannot run here (no shell), so this file is written by hand.

Target: `ios/Aniswift/CatalogScreens.swift`. Mode: Operate. Trend before this run: 30, 31, 34, 34, 35 out of
40 and 16, 17, 17, 17, 17 out of 20.

## Landed since pass 5

| Pass 5 issue | State now |
| --- | --- |
| [P2] Keyboard coverage was two controls, and refresh had no visible control to hang from | Fixed: a Refresh control in the list's, Discover's and the Feed's bar, each with Command-R; the Feed's existing refresh gained the same shortcut and a busy spinner |
| [P3] Empty states split between two grammars | Open |
| [P3] The quiet band under a title's name is centred where the page is left-aligned | Open |
| [P3] The shortcuts are unverified on a hardware keyboard | Open |

## What the refresh control does

A list, Discover and the Feed now read themselves again from one press in the bar, and each shows a spinner
while it works instead of a dead arrow: the pull-to-refresh in a press, for a reader who is not at the top of
the page. The three tabs answer a keyboard the same way (Command-R), which is also the first of the shortcuts
to be a control a pointer user can see rather than an invisible command.

## Design Health Score

| # | Heuristic | Score | Key Issue |
|---|-----------|-------|-----------|
| 1 | Visibility of System Status | 4 | Skeletons, saved-data notes, busy rows, refresh spinners |
| 2 | Match System / Real World | 3 | MAL's vocabulary; "restacks" stays jargon |
| 3 | User Control and Freedom | 4 | A step and a removal both undo |
| 4 | Consistency and Standards | 4 | One edge, corner, press, panel, failure and refresh |
| 5 | Error Prevention | 3 | Removal asks; edits disable while saving |
| 6 | Recognition Rather Than Recall | 4 | Remembered filters, recents, snapshots, visible sort |
| 7 | Flexibility and Efficiency | 4 | Refresh on every list-like tab, an editor and a filter sheet from the keyboard |
| 8 | Aesthetic and Minimalist Design | 4 | One heading per screen |
| 9 | Error Recovery | 4 | Every failure keeps the screen and says why |
| 10 | Help and Documentation | 3 | Signed-out panels, section footers, `DESIGN.md` |
| **Total** | | **36/40** | Excellent, minor polish only |

## Audit Health Score

| # | Dimension | Score | Key Finding |
|---|---------------------------|-------|-------------|
| 1 | Accessibility | 4 | Contrast, 44pt, scaling, labels, Reduce Motion, spoken failures |
| 2 | Performance | 3 | Downsampled art, prefetch, snapshots, lazy stacks |
| 3 | Appearance & Theming | 3 | Tokens complete; one appearance, a stated decision |
| 4 | Platform Conformance | 4 | Native throughout |
| 5 | Adaptivity | 3 | Width caps and sidebar tabs; landscape and Stage Manager unseen |
| **Total** | | **17/20** | Good |

## Remaining Priority Issues

1. [P3] Empty states still come in two grammars: a hand-built page block on the lists, the Feed and the
   catalog, `ContentUnavailableView` elsewhere. `DESIGN.md` says so, so it is a decision left open, not drift.
2. [P3] The quiet band under a title's name is centred, where every fact on the page below is left-aligned.
3. [P3] Tab switching has no shortcut; the tab bar stays the only way to move between the five tabs.
4. [P3] Command-R, Command-E and Command-Shift-F still need a device with a hardware keyboard.
