# Aniswift app UI, design critique pass 5

Method: design review only (detector not applicable, native platform). Same method as passes 1 to 4; the
skills' databases and the critique-storage helpers cannot run here (no shell), so this file is written by hand.

Target: `ios/Aniswift/TitleScreen.swift`. Mode: Operate. Trend before this run: 30, 31, 34, 34 out of 40 and
16, 17, 17, 17 out of 20.

## Landed since pass 4

| Pass 4 issue | State now |
| --- | --- |
| [P2] The title header's opening was the densest thing in the app | Fixed: the opening is the poster and the name, with one quiet band of figures and credits under it, and the edit controls start the page below |
| [P2] Keyboard coverage is two controls | Open |
| [P3] Empty states split between two grammars | Open |
| [P3] The two shortcuts are unverified on a hardware keyboard | Open |

## What the header does now

The poster (144, scaled) and the name (`.title2.bold`) are the only two loud elements. Under them sit the
figures as one row of `.subheadline` mono values under `.caption2` labels — they were `.title3.bold`, a second
and third heading competing with the name — then the studios or authors as `.footnote` links, then the original
title. Four blocks of heavy type became one identity and one quiet band. The status, progress and score controls
start the page at 22 points under the opening rather than at 14.

## Design Health Score

| # | Heuristic | Score | Key Issue |
|---|-----------|-------|-----------|
| 1 | Visibility of System Status | 4 | Skeletons, saved-data notes, busy rows, airing state |
| 2 | Match System / Real World | 3 | MAL's vocabulary; "restacks" stays jargon |
| 3 | User Control and Freedom | 4 | A step and a removal both undo |
| 4 | Consistency and Standards | 4 | One edge, corner, press, panel and failure grammar |
| 5 | Error Prevention | 3 | Removal asks; edits disable while saving |
| 6 | Recognition Rather Than Recall | 4 | Remembered filters, recents, snapshots, visible sort |
| 7 | Flexibility and Efficiency | 2 | Two accelerators; no tab or refresh shortcut |
| 8 | Aesthetic and Minimalist Design | 4 | One heading per screen; the opening no longer competes |
| 9 | Error Recovery | 4 | Every failure keeps the screen and says why |
| 10 | Help and Documentation | 3 | Signed-out panels, section footers, `DESIGN.md` |
| **Total** | | **35/40** | Good, at the ceiling of the band |

## Audit Health Score

| # | Dimension | Score | Key Finding |
|---|-----------|-------|-------------|
| 1 | Accessibility | 4 | Contrast, 44pt, scaling, labels, Reduce Motion, spoken failures |
| 2 | Performance | 3 | Downsampled art, prefetch, snapshots, lazy stacks |
| 3 | Appearance & Theming | 3 | Tokens complete; one appearance, a stated decision |
| 4 | Platform Conformance | 4 | Native throughout |
| 5 | Adaptivity | 3 | Width caps and sidebar tabs; landscape and Stage Manager unseen |
| **Total** | | **17/20** | Good |

## Remaining Priority Issues

1. [P2] Keyboard coverage is two controls: refresh and tab switching need a visible control to hang from.
2. [P3] Empty states still come in two grammars, the page block and `ContentUnavailableView`.
3. [P3] The quiet band under a title's name is centred; a long studio list then reads as a paragraph of links
   where the page elsewhere lists facts left-aligned.
4. [P3] The two shortcuts need a device with a hardware keyboard to confirm.
