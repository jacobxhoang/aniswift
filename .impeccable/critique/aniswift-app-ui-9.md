# Aniswift app UI, design critique pass 9

Method: design review of the source against `PRODUCT.md`, `DESIGN.md` and the native platform reference. The
skill's launcher and detector cannot run here (no shell), so this file is written by hand, as passes 1 to 8 were.

Target: the app's screens and the Home Screen widget surface. Mode: Operate.
Trend before this run: 30, 31, 34, 34, 35, 36, 37, 36 out of 40 and 16, 17, 17, 17, 17, 17, 16 out of 20. The dip
in pass 8 was the widget surface drifting from the app it belongs to; this pass checks whether that closed.

## Landed since pass 8

| Pass 8 issue | State now |
| --- | --- |
| [P2] The countdown was green in the widget and amber in the app for the same state | Fixed: the widget's countdown takes the app's two states, amber while an aired episode is unwatched and green once caught up |
| [P2] The widget's amber and green were the system's, not the app's measured pair | Fixed: `AiringInk` carries `Palette.airingBehind` and `Palette.airingCaughtUp` at their values, light and dark, so both appearances clear 4.5:1 on either card |
| [P2] The **+1** was 40×24 pt | Fixed: the capsule still draws slim, but the button's frame and hit area are 44×44 |
| [P3] The small Next Episode card carried no **+1** without saying so | Fixed in words: the gallery description names which sizes have the button |
| [P3] About carried engineering strings under user-facing rows | Fixed: the section is headed **Widget diagnostics** |
| [P3] The App Group is read through a private symbol | Recorded, not removed: `ARCHITECTURE.md` risk 25 names the symbol, the `dlsym` fallback and why no review would accept it |

## Design Health Score

| # | Heuristic | Score | Key Issue |
|---|-----------|-------|-----------|
| 1 | Visibility of System Status | 4 | Skeletons, saved-data notes, busy rows, a written snapshot |
| 2 | Match System / Real World | 3 | "restacks" is still jargon; the widget now says "behind" and "caught up" plainly |
| 3 | User Control and Freedom | 4 | A step and a removal both undo |
| 4 | Consistency and Standards | 4 | One amber, one green and one countdown meaning across the app and its cards |
| 5 | Error Prevention | 3 | Removal asks; edits disable while saving |
| 6 | Recognition Rather Than Recall | 4 | Remembered filters, recents, snapshots, visible sort |
| 7 | Flexibility and Efficiency | 4 | Refresh, an editor and a filter sheet from the keyboard |
| 8 | Aesthetic and Minimalist Design | 4 | One heading per screen, one row per idea |
| 9 | Error Recovery | 4 | Every failure keeps the screen and says why |
| 10 | Help and Documentation | 4 | Every dead end names the step out; the widget's empty state named the signing fault |
| **Total** | | **37/40** | **Excellent** |

## Audit Health Score

| # | Dimension | Score | Key Finding |
|---|-----------|-------|-------------|
| 1 | Accessibility | 4 | 44 pt targets, measured contrast in both appearances, labels, Reduce Motion |
| 2 | Performance | 3 | Downsampled art, prefetch, snapshots, lazy stacks; a timeline builds two requests |
| 3 | Appearance & Theming | 3 | The palette is complete in the app but written twice, once per target |
| 4 | Platform Conformance | 3 | Native throughout; one private symbol behind the App Group read |
| 5 | Adaptivity | 3 | Width caps and sidebar tabs; landscape and Stage Manager unseen |
| **Total** | | **17/20** | **Good** |

## Platform Conformance verdict

Passes as a native app: system list and sheets, `ContentUnavailableView` for the one empty state, SF Symbols
throughout, one tint, a glass control only where the platform has one, and a widget that now speaks the app's own
colour language instead of the system's. The one blemish is deliberate and documented.

## Remaining Priority Issues

1. [P3] The palette is written twice: `AiringInk` in the extension repeats two of `Palette`'s values because the
   two targets share no module. A small file added to both would close it, and the next colour change would then
   land once.
2. [P3] The widget's type sizes are fixed, so at the largest accessibility sizes a card clips rather than scaling;
   it drops to one row at that size, which is the most a widget can do, but the type itself does not grow.
3. [P3] Landscape, Split View and Stage Manager have still not been seen on a device, which is the one thing
   keeping adaptivity at 3.

## Patterns & systemic issues

- Every finding this pass is a follow-through on one earlier decision, which is what a good pass looks like: the
  widget surface now matches the app it belongs to rather than gaining its own conventions.
- The duplication that remains is structural (two targets, one design system), not stylistic.

## Positive findings

- The two airing states are now one meaning in two places: a list row, a title page and a widget all say amber for
  behind and green for caught up, with the same measured shades.
- A widget's failure is still diagnoseable from the phone: the diagnostics section reads the signature back rather
  than asking the reader to guess.
- The app's Reduce Motion, haptics, VoiceOver labels, one-panel failures and one empty state survived four passes of
  widget work unchanged.

## Recommended actions

1. **[P3] `$impeccable extract`**: move the two airing colours into a file both targets compile, so the palette has
   one home.
2. **`$impeccable polish`** last: a pass over the widget's type at accessibility sizes is the only visual work left.
