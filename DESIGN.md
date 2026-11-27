# Aniswift interface

The app's own reference for what it looks like, so a change can be checked against a stated decision instead
of a guess. It covers the app UI only; `ARCHITECTURE.md` covers structure, providers and caching.

**Mode:** Operate. The reader is completing a task — finding a title, moving an episode, reading a synopsis —
so precision and consistency outrank expression, and the brand lives in exact details rather than in effects.

**Platform:** native iOS 17 and newer, SwiftUI throughout, iPhone and iPad.

## The world: a cinema ledger

Aniswift is a record book for what you have watched, drawn as a dark ledger rather than a shelf of artwork.
The canvas is black, content sits on quiet cards edged with one hairline, and figures are set in monospaced
digits under small uppercase labels. Posters are the only saturated colour on the page; everything else is
white at a few fixed strengths plus one accent the reader chooses. No gradients, no ornament, no second
accent. A screen should read like a page of a ledger that happens to carry posters.

The dark appearance is deliberate, not an omission: the app is a dark-room object, posters glow against the
black, and a light mode would need its own contrast pass on every token. There is therefore no appearance
switch and `.preferredColorScheme(.dark)` is set once at the root.

## Colour

One accent at a time, chosen in Settings (White by default, plus eight others), applied as the tint to
controls, links and the in-app browser. Everything else comes from `Palette` in `AniswiftApp.swift`:

| Token | Value | Use | Contrast on the canvas / on a surface |
| --- | --- | --- | --- |
| `background` | black | every page | — |
| `surface` | white 12% | a card, a chip's fill source, an editor panel | — |
| `sheet` | white 8% | the editor sheet behind a system Form | — |
| `hairline` | white 34% | poster rims, panel edges, capsules, dividers | about 3:1 / 3:1 |
| `border` | white 46% | an active or selected control | about 4.5:1 / 4.5:1 |
| `fill` | white 12% | behind a chip that is on | carries no boundary |
| `airingBehind` | amber | an aired episode is still unwatched | text-safe |
| `airingCaughtUp` | green | every aired episode is watched | text-safe |
| `progress` | green | the swipe that adds an episode or a chapter | fill only |

Rules: a boundary an edge carries clears 3:1 non-text contrast, and no view states a colour of its own.
Colour never carries a state alone — an airing row says "You are behind." for VoiceOver, and a chosen chip
takes a checkmark as well as a fill.

## Layout

`LedgerLayout` in `AniswiftApp.swift` names the scale; views do not pick their own numbers.

- Page inset 20, gap 12, section gap 28.
- Corners: 7 for a row's thumbnail and a chip, 8 for a poster, 12 for a panel. A panel's corner is
  `panelRadius` everywhere, through `ledgerPanel`.
- Poster ratio 0.685; shelf posters 116 wide and a title header's poster 144, both scaled by Dynamic Type up
  to 1.4× and then capped.
- Long content is capped: 800 for a page, 640 for a sheet, 480 for a header's figures, so an iPad reads a
  column rather than a stretched phone.

## Type

System text styles only, never a fixed point size. Names are `.headline`, `.subheadline` or `.body`;
captions are `.caption`; a figure is `monospacedDigit()`. An uppercase label over a value uses `.caption2` or
`.footnote` with `.medium` or `.semibold`. Numbers go through `Double.ledgerDecimal(_:)`, so a mean score
reads "8.40" on every locale, and a header draws a figure only where it has one — never an em dash.

A title page's opening is two things: the poster and the name. Its figures, its studios or authors and the
original title sit under them as one band of small type (`.subheadline` figures, `.footnote` credits, the name
at `.title2`), and the status, progress and score controls belong to the page below rather than to the opening.
One heading per screen is the rule; a second one competing with it flattens the hierarchy.

## Components

One component per job, drawn from `AniswiftApp.swift`:

- `LedgerShelf` — every horizontal carousel; snapping, gutters and insets come from here.
- `LedgerSectionTitle` and `LedgerViewAll` — one heading and one "see everything" link.
- `CoverTile`, `PosterShelf`, `Rail`, `TitleRow`, `PortraitCard` — posters and people; each presses through
  `LedgerTileButtonStyle`, reads as one VoiceOver element, and a poster's score is named out of ten.
- `ledgerPanel` — the one card. `LedgerProblem` and `SavedDataNote` are the notice family on top of it, and
  `LedgerFailureBar` is the app's own failure at the bottom edge with a Dismiss.
- `ledgerGlassButton`, `ledgerGlassBadge`, `ledgerGlassCircle`, `ledgerProminentButton` — the controls, on
  Liquid Glass for iOS 26 and a material or bordered fallback below it.
- `FilterChip` — a choice that is on says so with a checkmark as well as a fill.
- `ListStatusHeader` — a status group's heading, with its count and its collapsed state.

An empty state is the system's `ContentUnavailableView`, drawn through `LedgerEmpty`, so every page states it
the same way: what is missing, one line of why, and the step out of it (the catalog, the search cleared, Clear
Filters). A signed-out tab is a different thing and always wears the panel.

## Interaction

- A press is a small scale and a dim with no layout shift, and none of it under Reduce Motion.
- A swipe on a list row adds an episode or removes the entry; both answer a six-second **Undo** bar that
  names the row and the value it now holds. A removal is never a question.
- A long press on a poster opens its quick actions over the poster itself.
- Destructive confirmations are reserved for what cannot be undone; a removed entry can.
- Haptics: `.sensoryFeedback` on a control whose state changed, and `Haptics.success()` or `.error()` when a
  save lands or a request fails.
- Motion is short and purposeful: `.snappy(duration: 0.22)` for a bar or a sheet, `.easeOut(0.12)` for a
  press, a 1-second pulse for a skeleton. Every one of them is skipped under Reduce Motion.
- A failure never takes the screen: it arrives in the notice panel where the reader is and is announced.
- A link goes where it already belongs: a Twitter, Instagram or Facebook link opens its app when installed and its
  page when it is not, and every other link keeps the browser chosen in Settings. A handle is a link only where the
  line names one of those, and Instagram's bare handle counts because that is how it is written.

## Copy

Sentences are plain and specific: "Could not load more entries.", not "Something went wrong" alone. A row
names what it opens or sets and nothing more; an explanation of a section lives in its footer. A settings
value is read in the app's own English (a period before the decimals, a comma between thousands). Region
language comes from MyAnimeList — "Watching", "On hold", "Plan to watch", "interest stacks" — and is not
renamed.

## Accessibility

Every control is at least 44 points. A decorative glyph beside text is hidden from the accessibility tree; a
glyph that is the only content carries a label. A poster, a portrait and a row each read as one element with
its state named. Text scales with Dynamic Type and artwork follows to 1.4×; nothing clips at the accessibility
sizes. Reduce Motion is honored at every transition, and the failure bar is posted as an announcement.

## Open items

- Keyboard accelerators: Command-1 to Command-5 choose a tab, Command-R refreshes a list or Discover, Command-E
  opens a title page's editor, and Command-Shift-F a list's sort and filter sheet.
