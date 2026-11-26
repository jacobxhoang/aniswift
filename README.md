# Aniswift

Aniswift is a native anime and manga tracker for iPhone and iPad. Browse the catalog, track progress on
MyAnimeList, follow friends’ public activity, and read title reviews and interest stacks in the app. It is
built with SwiftUI and talks directly to public APIs — there is no backend, account system, or database of
its own.

## Features

- **Anime and Manga lists** — status groups, a Sort and Filter sheet for the order, direction, status, format
  and entry filters, search, pagination, swipe-to-update progress, swipe to
  remove, and a full editor for scores, repeat counts, dates, notes and custom lists.
- **Discover** — seasonal and ranked shelves, per-kind search, and genre, theme, studio and producer facets.
- **Title pages** — summary, metadata, relations, characters, recommendations, trailer, theme songs, reviews,
  interest stacks, and friends’ list activity, plus the countdown to the next episode of an anime that is still
  on the air. Tapping a poster shows it full screen, where it zooms on a
  double tap or pinch and closes from the glass X. Characters open their own
  profile, their voice actors and a manga’s authors open a page of their roles and staff credits.
- **Friends feed** — public updates from MyAnimeList friends, older pages, and native friend profiles with
  statistics, favorites and recent activity.
- **Profile** — account statistics, friends, public favorites (anime, manga, characters and people), custom
  lists, and a share link to the MyAnimeList profile.
- **Settings** — accent color, preferred title language, in-app link handling, a post-completion score prompt,
  preferred launch screen, iOS 26 tab-bar behavior, cache clearing, per-kind control over what a title page
  shows (including one switch that hides everything below its summary), profile appearance switches, an AniList
  sign-in with its lists read-only, plus About Aniswift and sign out.

## Requirements

- iPhone or iPad running iOS 17 or newer.
- Xcode 26 and the iOS 26 SDK to build from source.
- A MyAnimeList API application with the redirect URL `org.aniswift.ios://oauth` for sign-in. Its 32-character
  iOS Client ID goes in `Info.plist` (`AniswiftMALClientID`) or the `MAL_IOS_CLIENT_ID` CI secret before a build:
  the app has no field for it.
- No AniList app is needed for the read-only AniList section: the build ships a client ID, and you can put your
  own in `Info.plist` (`AniswiftAniListClientID`) instead.

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
- [Architecture and API analysis](ARCHITECTURE.md)
- [iOS releases](https://github.com/jacobxhoang/aniledger/releases)

## Releases

| Channel | What it is | Download |
| --- | --- | --- |
| Nightly | The tip of `main`, rebuilt into one rolling prerelease on every push | [Aniswift-Nightly-Unsigned.ipa](https://github.com/jacobxhoang/aniledger/releases/download/nightly/Aniswift-Nightly-Unsigned.ipa) |
| Stable | A tagged build, published on `ios-v*` | [Releases](https://github.com/jacobxhoang/aniledger/releases) |

Both are unsigned device builds: sign one with your own profile, or import it into a sideloading tool, before
installing it on an iPhone or iPad.

## Repository layout

```text
ios/
  Aniswift/          SwiftUI app sources and assets
  AniswiftTests/     Swift Testing suites for decoding, titles, dates, stack links, store sync and OAuth callbacks
  Aniswift.xcodeproj Xcode project and shared scheme
  README.md           Setup, feature, settings and release guide
.github/workflows/    Build, format, test and release workflow
ARCHITECTURE.md       Project structure, API inventory, caching and risk analysis
```
