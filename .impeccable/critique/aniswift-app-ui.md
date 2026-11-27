# Aniswift app UI, design critique and source audit

Method: design review only (detector not applicable, native platform). Native guidance from the
impeccable skill's `reference/critique.md` and `reference/audit.native.md`, plus the ui-ux-pro-max
`references/pro-rules.md` priority table. The skills' searchable databases and the critique-storage
helpers could not run: this session has no shell. This file is the snapshot, written by hand.

Target: `ios/Aniswift/` (AniswiftApp.swift, CatalogScreens.swift, TitleScreen.swift,
CharacterScreen.swift, SettingsScreen.swift). Mode: Operate.

## Design Health Score

| # | Heuristic | Score | Key Issue |
|---|-----------|-------|-----------|
| 1 | Visibility of System Status | 4 | Skeletons, saved-data notes, busy titles, airing state, refresh notes |
| 2 | Match System / Real World | 3 | Domain language correct; "restacks" and "interest stacks" are MAL jargon |
| 3 | User Control and Freedom | 3 | Swipe removal has Undo; a score change has none after the sheet closes |
| 4 | Consistency and Standards | 3 | Components consistent; error and empty-state grammar split two ways |
| 5 | Error Prevention | 3 | Removal asks; edits disable while saving; no draft safety on long forms |
| 6 | Recognition Rather Than Recall | 4 | Remembered filters, search recents, snapshots, always-visible sort label |
| 7 | Flexibility and Efficiency | 2 | No keyboard shortcut anywhere; no bulk or status-only action |
| 8 | Aesthetic and Minimalist Design | 3 | Disciplined, one accent; title header opening is crowded |
| 9 | Error Recovery | 3 | Plain messages and retry everywhere; one global blocking alert |
| 10 | Help and Documentation | 2 | About screen and hints; no first-run help, no inline explanation |
| **Total** | | **30/40** | Good |

## Audit Health Score

| # | Dimension | Score | Key Finding |
|---|-----------|-------|-------------|
| 1 | Accessibility | 3 | 59 labels/hints, Reduce Motion honored; 38pt control, footnote Retry targets |
| 2 | Performance | 3 | Downsampled images, prefetch, snapshots, lazy stacks; sorts rebuilt per body pass |
| 3 | Appearance & Theming | 3 | Semantic tokens, one raw tint beside them; contrast floor under 3:1 |
| 4 | Platform Conformance | 4 | Native tabs, glass, swipe actions, context menus, ShareLink, no web shapes |
| 5 | Adaptivity | 3 | Width caps, ViewThatFits, sidebar tabs; title header poster does not scale |
| **Total** | | **16/20** | Good |

## Priority Issues

1. [P1] Signed-out lists are a bare button. `CatalogScreens.swift:248`. No copy, no catalog door.
2. [P1] Two error surfaces. `AniswiftApp.swift:59` alert vs `LedgerProblem` panels.
3. [P1] Separator and border tokens under the 3:1 non-text floor. `AniswiftApp.swift:219-221`.
4. [P2] 38pt round sort-direction control. `CatalogScreens.swift:701-706`.
5. [P2] Three panel treatments and two radii for one card idea.
6. [P2] Title header poster fixed at 144x208 while other artwork scales.
7. [P2] No keyboard accelerators on iPad.
8. [P3] Settings prints a detail line inside the AniList section.
9. [P3] `LedgerProblem` / `SavedDataNote` Retry buttons have no 44pt target.
