# Aniswift UX evaluation

## What holds

- Every action is reversible: a removal and a progress step each keep six seconds of Undo, an editor's X asks before it
  discards, and no destructive action is a one-tap default.
- The app commits nothing to itself: no account, no analytics, no notifications, no streaks, no re-engagement.
- A failure keeps the page: the saved copy with a note, a retry in place, and the app's own failure at the bottom
  edge rather than over the screen.
- Every dead end names the step out: an empty list offers the catalog, a filtered one offers Clear Filters, a
  signed-out tab names the way in.
- No manipulative pattern is present: no prechecked consent, no fabricated scarcity or urgency, no confirmshaming, no
  hidden cost, no disguised ad, no attention bait, no obstruction interstitial.
- A list says where its reading stands: a group count takes a plus while pages are still being read, a loading row
  offers the next page, and a list that has read everything says so under its last row.
- A hardware keyboard reaches what the app offers: Command-1 through Command-5 choose a tab, Command-R refreshes a
  list, Discover or the Feed, Command-E opens a title's editor, and Command-Shift-F opens a list's sort and filter.
  The rows are `NavigationLink` controls, which Full Keyboard Access focuses and activates.

## What fails

Nothing the app can change from source. The one failure this evaluation found is fixed: a MyAnimeList edit is written
into AniList as well, and Settings said nothing about it. The section's footer now states that the copy happens and
that nothing is read back.

## What is missing

- Landscape, Split View and Stage Manager have not been seen on a device, so the layout's adaptation is asserted by the
  code rather than observed.

## Considered and refused

- **Interest stacks and restacks stay as MyAnimeList names them.** They are jargon to a newcomer and the exact words the
  one reader already uses, and inventing a synonym would rename a provider's own fact.
- **The friends feed's pull-to-refresh stays.** The content genuinely changes between pulls and the reader pulls
  deliberately, so it is not a lever that might reveal something.
- **The lists read every page without a stop.** The stop is the last row, which now says so in words, and a personal
  tracker's job is the whole list rather than a session that ends early.
