# Aniswift — design and resilience sweep

Skills run: **evaluate** (heuristic evaluation, severity ranking, routing) and **fortify** (state inventory, edge
case catalog, stress prompts). Both read the source; neither can run a browser or a detector here. `impeccable` was
run twice already (passes 8 and 9) and its findings are in `.impeccable/critique/`; the remaining design skills —
present, storytelling, wireframe, journey, strategize, investigate, measure, blueprint, specify, transpose,
localize, philosopher — describe work this app has no open surface for, and the two copy skills were applied below
where copy is a finding.

## Anti-Pattern Verdict

Clean. No confirmshaming, no prechecked consent, no fabricated urgency, no infinite scroll, no streak mechanics.
The one dark-pattern-adjacent thing in the app is a deliberate one: the app's numbers are written in English
conventions whatever the device's locale, which is stated in `DESIGN.md` and is not a manipulation.

## Priority Issues

### Major

**Opening a list reads every page of it before the reader gets there**
- **What happens:** `Store.loadWholeList` walks the list a page at a time up to fifty pages as soon as the tab
  opens, so a 2,000-row list costs twenty requests and a 5,000-row one fifty before the page settles.
- **Why it matters:** on a slow connection the list is busy for a minute, and the requests are made for rows the
  reader may never scroll to.
- **Breaks:** flexibility and efficiency of use; also the loading state, which stays in its skeleton longer than
  the first screen needs.
- **Change:** read the pages the reader scrolls into, with the loaded count against MyAnimeList's total, and keep
  the eager read only for the first page.

**The widget's +1 has no failure state**
- **What happens:** the button writes to MyAnimeList from the extension; when the write fails nothing changes on
  the card, so a failed tap and a missed tap look identical.
- **Why it matters:** a reader taps again and either doubles an episode or learns the button cannot be trusted,
  and the app's one failure surface — the bar at the bottom edge — is in the other process.
- **Breaks:** help users recognize, diagnose and recover from errors; a silent failure in a control whose whole
  job is a write.
- **Change:** leave the row as it is and mark the card, or record the failure in the snapshot so the app reports
  it on its next foreground.

### Minor

**Settings is six screens and thirty-four toggles with no search**
- **What happens:** Behavior, Details Page (33 switches), Profile (8), Launch Sections, Face ID and accent/appearance
  are separate screens with no way to search a setting by name.
- **Why it matters:** the reader knows the switch exists and cannot find it; the app's own vocabulary ("Sections
  Below Summary", "Preferred Title Language") is not guessable from the top level.
- **Breaks:** recognition rather than recall; flexibility and efficiency of use.
- **Change:** a search field over the settings tree, or a single Details Page screen grouped by the kind, with the
  group names as anchors.

**Discover has no saved copy, while lists and the feed do**
- **What happens:** offline, Anime, Manga and Feed keep their snapshots behind a "Showing saved data" note;
  Discover drops to a failure panel, because its ten shelves live only in the five-minute response cache.
- **Why it matters:** the one tab that is browsable without a connection in other apps is the one that stops
  working here, and the reader has to remember that the app is inconsistent.
- **Breaks:** error recovery; consistency and standards.
- **Change:** write the last set of shelves into the same snapshot store the lists use, with the same note.

**Every string is a literal with a hand-built plural**
- **What happens:** copy is written inline (`"\(behind) episodes behind"`, `episode\(count == 1 ? "" : "s")`,
  "1/12") and there is no String Catalog, so the app is English by construction rather than by setting.
- **Why it matters:** the app is English-only by decision, but the decision is now load-bearing in every file; a
  second language would be a pass over every view, and plurals would need rewriting rather than translating.
- **Breaks:** internationalization readiness.
- **Change:** move the reader-facing strings into a catalog and use a plural rule at the four places that count
  episodes or chapters, which also gives the English copy one home.

### Cosmetic

**One widget string speaks in build terms**
- **What happens:** a widget with no App Group says "This build has no App Group, so the widget cannot read your
  list.", which is exactly what its owner needs and nothing a second reader could act on.
- **Why it matters:** it is the one string whose audience is a developer; the rest of the app speaks to a reader.
- **Breaks:** match between system and the real world.
- **Change:** keep the sentence — it is deliberately diagnostic — and let the section it belongs to carry the
  build vocabulary so the widget's own line stays a sentence about the list.

## State Inventory

| Where | State | What the reader sees and can do | Recovery | Severity |
| --- | --- | --- | --- | --- |
| Any widget card | The +1 write failed | The row is unchanged; nothing says the tap was received or refused | Tap again — with no way to tell the first tap from the second | Major |
| Any widget card | The signature carries no group | The card says so and offers nothing | Sign the build with a group-bearing certificate | Minor |
| Discover | Offline | A failure panel with Retry; the shelves that were on screen a minute ago are gone | Retry, or open Anime and Manga, which do keep their snapshots | Minor |
| A list, reading | A page in the middle of the eager read failed | The rows already read stay, the read stops, and the list's own retry says why | Retry, which re-reads from the first page | Minor |
| Settings → Details Page | Large text | The 33 switches scroll; no group is sticky | None needed | Cosmetic |
| Title page, offline | A title never opened before | The failure panel that every section uses | Retry | Handled |
| Lists, Feed, Profile | A saved snapshot older than its window | The snapshot, a note, and Retry | Retry, or pull to refresh | Handled |
| Lock screen | A device with no passcode | A sentence saying it cannot unlock | None — the platform's own limit | Handled |

## Edge Case Catalog

| Scenario | What the design does now | Change | Severity |
| --- | --- | --- | --- |
| A list with 5,000 rows | Fifty requests on open, every page read | Read on scroll, count against the total | Major |
| A title name of 200 characters | Clipped at the row's line limit, spoken in full | None | Handled |
| A widget tap while offline | The write fails silently | Mark the card or record the failure | Major |
| A session that expires while a widget is tapped | The write is refused; the card is unchanged | The app signs out with its own sentence on next launch, which is already the case; the card should not pretend it worked | Minor |
| German or Finnish copy, 40% longer | No catalog, so no expansion to test | Move strings into a catalog | Minor |
| A friend's profile with no friends | The shelf is absent, the section holds | None | Handled |
| A title with no episodes announced | The countdown says "Next episode in …" without an episode number | None — deliberate | Handled |
| Two list edits at once | The revision counter aborts the sync and re-syncs | None | Handled |

## Open Questions

- Should the remaining widget write failure be shown on the card's next reload, or only in the app on next
  foreground? A widget cannot raise an alert, and a card that marks a failure may outlive the failure.
- Is a list allowed to be read lazily at all, given that the search field inside a list searches only loaded
  rows? If the answer is no, the eager read is the price of that search and the finding becomes a note.

## Copy findings routed to the writing skill

- The details toggles name themselves well ("Sections Below Summary"), but the three settings screens' titles
  ("Behavior", "Details Page", "Profile") do not say which kind they configure; the first line of each screen could
  name the kind.
- "restacks" appears in interest-stack copy and is MyAnimeList's own word; every other place the app translates
  its vocabulary, so this one could read "stacks".
