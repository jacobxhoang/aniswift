# Aniswift app UI, design critique pass 3

Method: design review only (detector not applicable, native platform). Same method as the two earlier
snapshots; the skills' databases and the critique-storage helpers still cannot run (no shell), so this file is
written by hand.

Target: `ios/Aniswift/`. Mode: Operate. Trend before this run: 30/40 and 16/20, then 31/40 and 17/20.

## Landed since pass 2

| Pass 2 issue | State now |
| --- | --- |
| [P1] A failure reaches the reader twice over | Fixed: the root alert is gone, `LedgerFailureBar` draws the same notice panel at the bottom edge with a Dismiss, and the message is announced |
| [P2] No undo for a progress or score change | Fixed for progress: a step holds a `ListUndo`, so a swipe adds an episode and the bar takes it back; the editor sheet keeps its own Cancel |
| [P3] One raw green beside the palette | Fixed: `Palette.progress` |
| [P2] No keyboard accelerators | Open |
| [P3] Empty states split between two grammars | Open |

## Design Health Score

| # | Heuristic | Score | Key Issue |
|---|-----------|-------|-----------|
| 1 | Visibility of System Status | 4 | Skeletons, saved-data notes, busy rows, airing state |
| 2 | Match System / Real World | 3 | MAL's vocabulary; "restacks" stays jargon |
| 3 | User Control and Freedom | 4 | A step and a removal both undo; every sheet cancels |
| 4 | Consistency and Standards | 4 | One edge, one corner, one press, one failure grammar |
| 5 | Error Prevention | 3 | Removal asks; edits disable while saving |
| 6 | Recognition Rather Than Recall | 4 | Remembered filters, recents, snapshots, visible sort |
| 7 | Flexibility and Efficiency | 2 | No keyboard shortcut anywhere |
| 8 | Aesthetic and Minimalist Design | 3 | Restrained; the title header opening is dense |
| 9 | Error Recovery | 4 | Every failure keeps the screen, says why, offers a step |
| 10 | Help and Documentation | 3 | Signed-out panels and section footers explain |
| **Total** | | **34/40** | Good, at the top of the band |

## Audit Health Score

| # | Dimension | Score | Key Finding |
|---|-----------|-------|-------------|
| 1 | Accessibility | 4 | Contrast, 44pt targets, scaling, labels, Reduce Motion, spoken failures |
| 2 | Performance | 3 | Downsampled art, prefetch, snapshots, lazy stacks |
| 3 | Appearance & Theming | 3 | Semantic tokens now complete; one appearance by design |
| 4 | Platform Conformance | 4 | Native throughout |
| 5 | Adaptivity | 3 | Width caps and sidebar tabs; landscape and Stage Manager unseen |
| **Total** | | **17/20** | Good |

## Remaining Priority Issues

1. [P2] No keyboard accelerators: zero `keyboardShortcut`, on a surface that runs on iPad.
2. [P2] The dark appearance is a decision the repository never states; there is no `DESIGN.md` and no field
   for it, so it reads as an omission rather than a choice.
3. [P3] Empty states split between `ContentUnavailableView` and hand-built panels.
4. [P3] A notice panel is a flat surface where every other panel is a material.
