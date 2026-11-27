# Aniswift app UI, design critique pass 4

Method: design review only (detector not applicable, native platform). Same method as passes 1 to 3; the
skills' databases and the critique-storage helpers cannot run here (no shell), so this file is written by
hand. From this pass the project has a `DESIGN.md`, so the skill's context step has a document to read
instead of nothing.

Target: `ios/Aniswift/`. Mode: Operate. Trend before this run: 30, 31, 34 out of 40 and 16, 17, 17 out of 20.

## Landed since pass 3

| Pass 3 issue | State now |
| --- | --- |
| [P2] The dark appearance was an unstated decision | Fixed: `DESIGN.md` states it, with the reason and the absence of a light pass |
| [P2] No keyboard accelerators | Partly fixed: Command-E opens a title's editor, Command-Shift-F a list's Sort and Filter, both hanging from controls that already exist |
| [P3] A notice panel was a flat surface where every other panel is a material | Fixed: `ledgerNoticePanel` is `ledgerPanel` with its padding |
| [P3] Empty states split between two grammars | Open, and now written down as open |
| [P2] No visible control to hang a refresh or tab shortcut on | Open |

## Design Health Score

| # | Heuristic | Score | Key Issue |
|---|-----------|-------|-----------|
| 1 | Visibility of System Status | 4 | Skeletons, saved-data notes, busy rows, airing state |
| 2 | Match System / Real World | 3 | MAL's vocabulary; "restacks" stays jargon |
| 3 | User Control and Freedom | 4 | A step and a removal both undo; every sheet cancels |
| 4 | Consistency and Standards | 4 | One edge, corner, press, panel and failure grammar |
| 5 | Error Prevention | 3 | Removal asks; edits disable while saving |
| 6 | Recognition Rather Than Recall | 4 | Remembered filters, recents, snapshots, visible sort |
| 7 | Flexibility and Efficiency | 2 | Two accelerators; no tab or refresh shortcut |
| 8 | Aesthetic and Minimalist Design | 3 | The title header opening is dense |
| 9 | Error Recovery | 4 | Every failure keeps the screen and says why |
| 10 | Help and Documentation | 3 | Signed-out panels, section footers, `DESIGN.md` |
| **Total** | | **34/40** | Good, top of the band |

## Audit Health Score

| # | Dimension | Score | Key Finding |
|---|-----------|-------|-------------|
| 1 | Accessibility | 4 | Contrast, 44pt, scaling, labels, Reduce Motion, spoken failures |
| 2 | Performance | 3 | Downsampled art, prefetch, snapshots, lazy stacks |
| 3 | Appearance & Theming | 3 | Tokens complete; one appearance, now a stated decision |
| 4 | Platform Conformance | 4 | Native throughout |
| 5 | Adaptivity | 3 | Width caps and sidebar tabs; landscape and Stage Manager unseen |
| **Total** | | **17/20** | Good |

## Why the score did not move

Three fixes landed and none of them moved a heuristic: the keyboard gap was already scored 2 and two
accelerators out of the dozens a keyboard reader might want do not lift it to 3; the notice panel was a
consistency detail that heuristic 4 already scored 4 for; and stating the dark appearance in `DESIGN.md` makes
the decision legible without changing the interface. A flat cycle here means the remaining gains are in the
visible composition, not in the plumbing.

## Remaining Priority Issues

1. [P2] The title header's opening is the densest thing in the app: a 144-point poster, the name, the
   studio chips, up to three figures, three edit controls and the airing band, all inside one 20-point inset.
2. [P2] Keyboard coverage is two controls; a refresh and a tab switch need a visible control first, and a
   hidden command is not worth shipping unverified.
3. [P3] Empty states still come in two grammars, the page block and `ContentUnavailableView`.
4. [P3] The two new shortcuts are unverified: they need a device with a hardware keyboard.
