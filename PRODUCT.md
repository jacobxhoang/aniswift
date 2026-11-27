# Product

<!-- impeccable:product-schema 1 -->

## Platform

ios

## Users

One person: the owner, on his own iPhone and iPad. He keeps what he watches and reads tracked on MyAnimeList and wants
a native client for it, used in short sessions on a phone — check what aired, move an episode, look up a title. Nobody
else uses the app, there is no stranger to onboard, and there is no second account to design for.

## Product Purpose

Aniswift is a native anime and manga tracker that reads the catalog and writes to MyAnimeList without a backend of its
own. Success is three things: the list on the device matches the list on MyAnimeList, a title page draws its answers on
the first frame, and there is nothing to run, pay for or maintain on a server.

## Positioning

The app owns no account, database or server. MyAnimeList is the account, AniList is a one-way mirror, and Tenrai with
Jikan Edge is the catalog, so the whole product is third-party HTTP plus device storage. A neighbouring tracker with a
backend could match the features but not the posture: removing the server removes the data, the cost and the login. The
mirror copies changes into AniList and never reads them back, so AniList can never quietly become a second source of
truth.

## Operating Context

- Personal install from an unsigned device build, or built from source in Xcode 26 with the iOS 26 SDK. The deployment
  target is iOS 17.
- CI does the verification: format, then the test suites, then the unsigned IPA and the rolling nightly prerelease. On the
  owner's machine, building is the only step.
- One MyAnimeList API registration with the redirect URL `org.aniswift.ios://oauth`. The client IDs live in `Info.plist`
  at build time, and CI may overwrite MyAnimeList's from a secret; the app has no field for either.
- Settings are device-wide and never synced. Tokens and snapshots stay in the Keychain and the caches directory.
- The app is English throughout, written for its one reader rather than as marketing copy.

## Capabilities and Constraints

Confirmed capabilities: anime and manga lists with status groups, the sort and filter sheet, search and paging, swipe
progress and removal with an Undo, and the full editor; Discover with seasonal and ranked shelves, per-kind search and
the facet screens; title pages with summary, metadata, relations, characters, recommendations, the in-app trailer, theme
songs, reviews, interest stacks and friends' activity; the airing countdown and its amber/green row state; the friends
feed, friend profiles and a friend's own friends; the profile with statistics, favorites and custom lists; Settings,
About and the read-only AniList section.

Confirmed constraints:

- No backend, account system or database of its own: nothing is stored that could not be rebuilt from a provider.
- MyAnimeList is the account and the only write target. The AniList copy is permanent and one-way — read-only lists,
  never edited, never read back.
- The catalog is read from Tenrai first and Jikan Edge second. There is no bundled catalog.
- The trailer is YouTube's embed in a web view, not a native player: the player endpoint refuses the app and the watch
  page's formats arrive ciphered. Settled; do not reopen it.
- Scores cross between the two services on the 100-point scale, so a MyAnimeList 8 is AniList's 80.
- `project.pbxproj` is never edited by hand and the project is not file-system-synchronised, so a new Swift type goes
  into an existing file.
- The app draws in two appearances: a dark ledger and a light one, with the same tokens and rules in both, and
  Settings → Appearance chooses System, Light or Dark. The visual world and its tokens are recorded in `DESIGN.md`.
- Distribution beyond the owner's own devices is not planned, so no store listing, rating prompt or marketing surface is
  in scope.

## Brand Commitments

- The name is Aniswift, and the ledger idea behind the interface is settled. `DESIGN.md` holds the world, the tokens and
  the rules; future work keeps them rather than replacing them.
- The app is a tool, not a showcase: no marketing copy, no testimonials and no onboarding, because its reader already
  knows what it is for.
- Accents, title language, tab behaviour and the rest of the preferences belong to Settings. They are not a brand palette
  and not a selling point.

## Evidence on Hand

- Working source: `ios/Aniswift/` for the app and `ios/AniswiftTests/` for six Swift Testing suites.
- `ARCHITECTURE.md` records structure, providers, caching and risks; `DESIGN.md` records the interface. Both are kept
  accurate with every change.
- Live provider behaviour is documented in `ARCHITECTURE.md` section 13, from read-only calls to each service.
- Release artifacts exist as the nightly and tagged GitHub releases, both unsigned device builds.

Absent, and not to be invented: testimonials, customer quotes, benchmarks, pricing, download or user counts, and any
App Store presence.

## Product Principles

1. The account lives where it already is. Nothing here creates data that would have to be kept, migrated or deleted.
2. One source of truth per fact — MyAnimeList for the list, AniList for the schedule, Tenrai with Jikan for the catalog.
   Never a guess, and never a second copy.
3. A mirror never becomes a second account. AniList is written to and read, never edited, even when two-way would be
   easier.
4. A failure keeps the page. Saved data with a note, a retry in place, and the screen still usable.
5. The app explains itself once, where the reader is: an empty state names the step out and a signed-out tab names the
   way in, because there is nobody else to ask.
