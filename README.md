# Aniswift

Aniswift is a native anime and manga tracker for iPhone and iPad. Browse the catalog, track progress on
MyAnimeList, follow friends’ public activity, and read title reviews and interest stacks in the app. It is
built with SwiftUI and talks directly to public APIs — there is no backend, account system, or database of
its own.

## Features

- **Anime and Manga lists** — status groups, a Sort and Filter sheet for the order, direction, status, format
  and entry filters, search, pagination, swipe-to-update progress, swipe to
  remove, a full editor for scores, repeat counts, dates, notes and custom lists, and a way to start a rewatch of a
  completed title.
- **Discover** — seasonal and ranked shelves, per-kind search, and genre, theme, studio and producer facets.
- **Title pages** — summary, metadata, relations, characters, recommendations, trailer, theme songs, reviews,
  interest stacks, and friends’ list activity, plus the countdown to the next episode of an anime that is still
  on the air, taken from the schedule AniList publishes. A row of an airing anime carries the same line, in amber
  while you are behind and green once you have caught up. Tapping a poster shows it full screen, where it zooms on a
  double tap or pinch and closes from the glass X. Characters open their own
  profile, their voice actors and a manga’s authors open a page of their roles and staff credits.
- **Friends feed** — public updates from MyAnimeList friends, older pages, and native friend profiles with
  statistics, favorites, recent activity and the friend's own friends.
- **Profile** — account statistics, friends, public favorites (anime, manga, characters and people), custom
  lists, and a share link to the MyAnimeList profile.
- **Home Screen widgets** — **Last Updated Anime** and **Last Updated Manga**, small or medium, with each title's
  poster, a progress bar, the count and a **+1** that updates MyAnimeList without opening the app; **Next Episode**,
  in every size, with the countdown to each airing anime's next episode; and **Profile Statistics**, which draws the
  account's totals.
- **Settings** — appearance (System, Light or Dark), accent color, preferred title language, an adult-content switch, in-app link handling, a post-completion
  score prompt, preferred launch screen, which list groups open first, a Face ID or passcode lock with its timer, iOS 26
  tab-bar behavior, cache and search-history clearing, per-kind control over what a title page
  shows (including one switch that hides everything below its summary), profile appearance switches, an AniList
  sign-in with its lists read-only, plus About Aniswift and sign out.

## Requirements

- iPhone or iPad running iOS 17 or newer.
- Xcode 26 and the iOS 26 SDK to build from source.
- A MyAnimeList API application with the redirect URL `org.aniswift.ios://oauth` for sign-in. The build carries an
  iOS Client ID in `Info.plist` (`AniswiftMALClientID`), which CI overwrites from the `MAL_IOS_CLIENT_ID` secret when
  one is set: the app has no field for it, so a build signs in with the ID it was built with.
- No AniList app is needed for the read-only AniList section: the build ships a client ID, and you can put your
  own in `Info.plist` (`AniswiftAniListClientID`) instead.
- The Home Screen widgets share an App Group with the extension, and the build uses whichever group its signature
  grants: `AppGroup.known` names the groups a sideload certificate carries and the app's own, and the first that
  opens wins. A signature that grants none of them still installs, but its widgets cannot read your list.

## Data sources

| Source | Used for |
| --- | --- |
| MyAnimeList | OAuth sign-in, private lists and list edits |
| Tenrai | Preferred catalog source for search, rankings, details, reviews and stacks |
| Jikan Edge | Catalog fallback and public friends, favorites, statistics and activity |
| AniList | Settings → AniList: sign-in and a read-only view of the account's lists |
| Device storage | Keychain tokens, list and feed snapshots, cached images and responses, preferences |

## Documentation

- [iOS setup, features and release guide](ios/README.md)
- [Product record: users, purpose and principles](PRODUCT.md)
- [Architecture and API analysis](ARCHITECTURE.md)
- [Interface reference: tokens, components and interaction rules](DESIGN.md)
- [UX evaluation: what holds and what is missing](evaluation-aniswift.md)
- [Decision log: each choice, its reason and what it rejected](decisions.md)
- [iOS releases](https://github.com/jacobxhoang/aniswift/releases)

## Releases

| Channel | What it is | Download |
| --- | --- | --- |
| Nightly | The tip of `main`, rebuilt into one rolling prerelease on every push | [Aniswift-Nightly-Unsigned.ipa](https://github.com/jacobxhoang/aniswift/releases/download/nightly/Aniswift-Nightly-Unsigned.ipa) |
| Stable | A tagged build, published on `ios-v*` | [Releases](https://github.com/jacobxhoang/aniswift/releases) |

Both are unsigned device builds: sign one with your own profile, or import it into a sideloading tool, before
installing it on an iPhone or iPad.

## Repository layout

```text
ios/
  Aniswift/          SwiftUI app sources and assets
  AniswiftWidgetExtension/  Last Updated and Profile Statistics Home Screen widgets
  AniswiftTests/     Swift Testing suites for decoding, titles, dates, stack links, store sync and OAuth callbacks
  Aniswift.xcodeproj Xcode project and shared scheme
  README.md           Setup, feature, settings and release guide
.github/workflows/    Build, format, test and release workflow
ARCHITECTURE.md       Project structure, API inventory, caching and risk analysis
PRODUCT.md            Product record: users, purpose, constraints and principles
DESIGN.md             Interface reference: tokens, components, interaction and copy rules
```
