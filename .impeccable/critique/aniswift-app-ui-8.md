# Aniswift app UI, design critique pass 8

Method: source audit against `PRODUCT.md`, `DESIGN.md` and the native platform reference. The skill's launcher
(`impeccable context`) and its detector cannot run here — there is no shell in this environment — so this file is
written by hand, as passes 1 to 7 were.

Target: the app's screens plus the Home Screen widget surface, which is new since pass 7 (`ios/AniswiftWidgetExtension`).
Mode: Operate. Trend before this run: 30, 31, 34, 34, 35, 36, 37 out of 40 and 16, 17, 17, 17, 17, 17 out of 20.

## Landed since pass 7

| Pass 7 issue | State now |
| --- | --- |
| [P3] Empty states came in two grammars | Holding: `LedgerEmpty` is still the one page-level empty state, and the widget extends it in its own words |
| [P3] Tab switching has no shortcut | Fixed: Command-1 to Command-5 select a tab |
| [P3] The quiet band under a title's name is centred where the page is left-aligned | Open, and deliberate |
| [P3] The three shortcuts need a hardware keyboard | Open, and unavoidable |
| — | New surface: four Home Screen widgets, with their own empty state, palette and hit targets — audited below |

## Design Health Score

| # | Heuristic | Score | Key Issue |
|---|-----------|-------|-----------|
| 1 | Visibility of System Status | 4 | Skeletons, saved-data notes, busy rows, a written snapshot |
| 2 | Match System / Real World | 3 | "restacks" is still jargon; the widget says "behind" plainly |
| 3 | User Control and Freedom | 4 | A step and a removal both undo |
| 4 | Consistency and Standards | 3 | The widget's countdown is green while the app's own row is amber for the same state |
| 5 | Error Prevention | 3 | Removal asks; edits disable while saving |
| 6 | Recognition Rather Than Recall | 4 | Remembered filters, recents, snapshots, visible sort |
| 7 | Flexibility and Efficiency | 4 | Refresh, an editor and a filter sheet from the keyboard |
| 8 | Aesthetic and Minimalist Design | 4 | One heading per screen, one row per idea |
| 9 | Error Recovery | 4 | Every failure keeps the screen and says why |
| 10 | Help and Documentation | 4 | Every dead end names the step out; About now names the signature's own facts |
| **Total** | | **36/40** | **Excellent** |

## Audit Health Score

| # | Dimension | Score | Key Finding |
|---|-----------|-------|-------------|
| 1 | Accessibility | 3 | The widget's **+1** is 40×24 pt, under the 44 pt target, and its green is the system's |
| 2 | Performance | 3 | Downsampled art, prefetch, snapshots, lazy stacks; the widget fetches posters and schedules in the timeline |
| 3 | Appearance & Theming | 3 | Tokens complete in the app; the widget re-states two colours as system values |
| 4 | Platform Conformance | 3 | Native throughout, but the group is read through a private Security symbol |
| 5 | Adaptivity | 3 | Width caps and sidebar tabs; landscape and Stage Manager unseen |
| **Total** | | **16/20** | **Good** |

## Platform Conformance verdict

Native, not a port: system list, sheets, `ContentUnavailableView`, SF Symbols, one tint, a Liquid Glass control
where a glass control belongs. Two things keep it from a clean pass — a widget that speaks a slightly different
colour language from the app it belongs to, and one private symbol behind the App Group read.

## Detailed findings

**[P2] The countdown is green in the widget and amber in the app for the same state**
- Location: `ios/AniswiftWidgetExtension/AniswiftWidgetExtension.swift`, `countdown`; the app's row is
  `CatalogScreens.airingLine`
- Category: Theming / Consistency
- Impact: a reader who has learnt "amber means I am behind" on a list row reads a green countdown above
  "8 episodes behind" and has to learn a second language on the Home Screen
- Recommendation: colour the widget's countdown with the same two meanings the app uses — amber while an aired
  episode is unwatched, green once caught up — and keep the system green only for the announcement colour of a
  card with nothing behind it. The extension cannot import `Palette`, so duplicate its two measured values as it
  already duplicates `WidgetRow`
- Suggested command: `$impeccable colorize`

**[P2] The widget's amber and green are the system's, not the app's measured pair**
- Location: same file, `countdown` and `state` (`Color.orange`, `Color.green`)
- Category: Accessibility / Theming
- Impact: `DESIGN.md` records `Palette.airingBehind` and `Palette.airingCaughtUp` as values that clear 4.5:1 on
  either canvas; the system's green is about 2.4:1 on the widget's light card, so the countdown fails contrast in
  the light appearance that the app supports
- Recommendation: carry the palette's own light and dark values in the extension and draw the widget's text with
  them, so both appearances clear the floor the app holds itself to
- Suggested command: `$impeccable colorize`

**[P2] The widget's **+1** is 40×24 pt**
- Location: same file, `AddOneButton`
- Category: Accessibility
- Impact: below the 44 pt target the app holds everywhere else; a widget button is the hardest one to hit, since
  it lives under a thumb on a Home Screen grid
- Recommendation: restore 44×44 (the capsule may still look slim: pad the label, not the frame), or drop the
  button from the constrained row and keep it on the size that has room
- Suggested command: `$impeccable adapt`

**[P3] The small Next Episode card carries no **+1**, while the larger ones do**
- Location: `AniswiftAiringRowView.small`
- Category: Consistency
- Impact: the same widget offers an action at one size and not another; a reader who picks small to keep it tidy
  loses the one interaction it had
- Recommendation: either give the small card a compact button on its count line, or say so in its gallery
  description so the size is chosen knowingly
- Suggested command: `$impeccable clarify`

**[P3] About carries engineering strings under user-facing rows**
- Location: `AniswiftApp.AboutScreen`, the Home Screen widgets section
- Category: Consistency
- Impact: bundle identifiers and group names break the rule that a settings row is its title alone; they are
  diagnostic, and they sit in the screen that explains the app rather than setting it
- Recommendation: keep them — they are the only way to read a signing problem back on the phone — but mark the
  section as diagnostic in its header, and leave the identifiers' monospaced footnote as it is
- Suggested command: `$impeccable clarify`

**[P3] The App Group is read through a private Security symbol**
- Location: `ios/Aniswift/Persistence.swift`, `AppGroup.signatureGroups`
- Category: Conformance
- Impact: `SecTaskCopyValueForEntitlement` is not public API; the runtime lookup keeps the app from failing to
  launch, but a future iOS may remove the symbol, and no App Store review would pass it
- Recommendation: keep the fallback as the normal path for any build that is not sideloaded, and note the symbol in
  `ARCHITECTURE.md`'s risk list where the other private constraints live
- Suggested command: `$impeccable harden`

## Patterns & systemic issues

- The widget target cannot see the app's tokens, so it re-states colour, type and spacing by hand. Two of the three
  findings above come from that one gap; a shared small file added to both targets would close it.
- Hit targets drift when a layout is tightened for width: the **+1** lost 4 points when the row was rebuilt.

## Positive findings

- The widget's empty state names the reason rather than repeating "open the app": a signing fault and an empty list
  read differently, which is rare even in first-party widgets.
- The small card is words alone, at a size that fills it, and the three sizes share one countdown and one state view,
  so they cannot drift apart.
- The Home Screen figures run through the app's own `ledgerDecimal`, so a day total reads "17.6" and not "17,6" on a
  device that writes a comma.
- The app's Reduce Motion, haptics, VoiceOver labels and one-panel failure model are still intact after the widget
  work.

## Recommended actions

1. **[P2] `$impeccable colorize`**: give the widget the app's two airing colours, and use them for the countdown
   and the behind line.
2. **[P2] `$impeccable adapt`**: restore the **+1** to a 44 pt target.
3. **[P3] `$impeccable clarify`**: say in the small card's gallery description that it has no button, and mark the
   About diagnostics section as diagnostic.
4. **[P3] `$impeccable harden`**: record the private symbol in the risk list.
5. **`$impeccable polish`** last, so the four fixes land as one pass.
