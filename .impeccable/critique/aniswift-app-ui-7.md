# Aniswift app UI, design critique pass 7

Method: design review only (detector not applicable, native platform). Same method as passes 1 to 6; the
skills' databases and the critique-storage helpers cannot run here (no shell), so this file is written by hand.

Target: `ios/Aniswift/CatalogScreens.swift` and the shared components in `ios/Aniswift/AniswiftApp.swift`.
Mode: Operate. Trend before this run: 30, 31, 34, 34, 35, 36 out of 40 and 16, 17, 17, 17, 17, 17 out of 20.

## Landed since pass 6

| Pass 6 issue | State now |
| --- | --- |
| [P3] Empty states came in two grammars | Fixed: `LedgerEmpty` draws the system's `ContentUnavailableView` for every page, and the two hand-built blocks on the lists became it |
| [P3] The Feed was the one signed-out tab that said it in bare text | Fixed: it wears the panel the lists and the Profile wear |
| [P3] The quiet band under a title's name is centred where the page is left-aligned | Open, and deliberate: the header is centred, the page is not |
| [P3] Tab switching has no shortcut | Open |
| [P3] Command-R, Command-E and Command-Shift-F need a hardware keyboard | Open |

## Design Health Score

| # | Heuristic | Score | Key Issue |
|---|-----------|-------|-----------|
| 1 | Visibility of System Status | 4 | Skeletons, saved-data notes, busy rows, refresh spinners |
| 2 | Match System / Real World | 3 | MAL's vocabulary; "restacks" stays jargon |
| 3 | User Control and Freedom | 4 | A step and a removal both undo |
| 4 | Consistency and Standards | 4 | One edge, corner, press, panel, failure, refresh and empty state |
| 5 | Error Prevention | 3 | Removal asks; edits disable while saving |
| 6 | Recognition Rather Than Recall | 4 | Remembered filters, recents, snapshots, visible sort |
| 7 | Flexibility and Efficiency | 4 | Refresh, an editor and a filter sheet from the keyboard |
| 8 | Aesthetic and Minimalist Design | 4 | One heading per screen |
| 9 | Error Recovery | 4 | Every failure keeps the screen and says why |
| 10 | Help and Documentation | 4 | Every dead end names the step out, and every signed-out tab explains itself |
| **Total** | | **37/40** | Excellent |

## Audit Health Score

| # | Dimension | Score | Key Finding |
|---|-----------|-------|-------------|
| 1 | Accessibility | 4 | Contrast, 44pt, scaling, labels, Reduce Motion, spoken failures |
| 2 | Performance | 3 | Downsampled art, prefetch, snapshots, lazy stacks |
| 3 | Appearance & Theming | 3 | Tokens complete; one appearance, a stated decision |
| 4 | Platform Conformance | 4 | Native throughout, and the empty state is the system's own |
| 5 | Adaptivity | 3 | Width caps and sidebar tabs; landscape and Stage Manager unseen |
| **Total** | | **17/20** | Good |

## Remaining Priority Issues

1. [P3] Tab switching has no shortcut: the tab bar is still the only way across the five tabs.
2. [P3] The three shortcuts need a device with a hardware keyboard; the 4 on flexibility rests on them.
3. [P3] Landscape, Split View and Stage Manager have not been seen on a device, which is the one thing keeping
   adaptivity at 3.
