# Aniswift app UI, design critique pass 2

Method: design review only (detector not applicable, native platform). Same method as
`aniswift-app-ui.md`; the skills' databases and the critique-storage helpers still cannot run (no shell),
so this snapshot is written by hand.

Target: `ios/Aniswift/`. Mode: Operate. Previous run: 30/40 and 16/20.

## What pass 1 asked for, and what landed

| Pass 1 issue | State now |
| --- | --- |
| Signed-out list tab was a bare button | Fixed: `ListsScreen.signedOut` panel with copy, the way in and the catalog |
| Two error surfaces (alert vs notice panel) | Open |
| Edges below the 3:1 non-text floor | Fixed: `hairline` 34%, `border` 46% |
| 38pt sort-direction control | Fixed: 44pt |
| Three panel materials and two radii | Radii unified through `ledgerPanel`; materials still split on purpose |
| Fixed 144x208 header poster | Fixed: `@ScaledMetric`, capped at 1.4x |
| No keyboard accelerators | Open |
| Settings printed a detail line in a row | Fixed: the section's footer |
| Notice Retry had no 44pt target | Fixed |

Found during pass 2 and fixed: the new signed-out panel was inset 10 points where the same panel on Profile
is inset 20; and portrait cards (cast, voice actors, friends, favorite characters and people) answered a touch
with `.plain`, so they had no press state while every poster tile had one.

## Design Health Score

| # | Heuristic | Score | Key Issue |
|---|-----------|-------|-----------|
| 1 | Visibility of System Status | 4 | Skeletons, saved-data notes, busy titles, airing state |
| 2 | Match System / Real World | 3 | MAL's own vocabulary throughout; "restacks" stays jargon |
| 3 | User Control and Freedom | 3 | Undo for a removal, none for a progress or score change |
| 4 | Consistency and Standards | 3 | Press and radius now uniform; failures still two surfaces |
| 5 | Error Prevention | 3 | Removal asks, edits disable while saving |
| 6 | Recognition Rather Than Recall | 4 | Remembered filters, recents, snapshots, visible sort |
| 7 | Flexibility and Efficiency | 2 | No keyboard shortcut anywhere |
| 8 | Aesthetic and Minimalist Design | 3 | Restrained; the title header opening is dense |
| 9 | Error Recovery | 3 | Plain messages and retry in place; one blocking alert |
| 10 | Help and Documentation | 3 | Signed-out panels and footers explain; no help screen |
| **Total** | | **31/40** | Good |

## Audit Health Score

| # | Dimension | Score | Key Finding |
|---|-----------|-------|-------------|
| 1 | Accessibility | 4 | Contrast, 44pt targets, scaling, labels, Reduce Motion all hold at source |
| 2 | Performance | 3 | Downsampled art, prefetch, snapshots, lazy stacks |
| 3 | Appearance & Theming | 3 | Semantic tokens, one raw green beside them, one appearance by design |
| 4 | Platform Conformance | 4 | Native throughout |
| 5 | Adaptivity | 3 | Width caps and sidebar tabs; landscape and Stage Manager unseen |
| **Total** | | **17/20** | Good |

## Remaining Priority Issues

1. [P1] A failure reaches the reader twice over: the root alert (`AniswiftApp.swift:59`) for `store.message`
   and a notice panel for the same class of failure.
2. [P2] No keyboard accelerators: zero `keyboardShortcut` in the app, on a surface that runs on iPad.
3. [P2] No undo for a progress or score change; only a removal keeps one.
4. [P3] One raw green (`CatalogScreens.swift:540`) beside the palette tokens.
5. [P3] Empty states still split between `ContentUnavailableView` and hand-built panels.
