# AniLedger

AniLedger is a native anime and manga tracker for iPhone and iPad. Browse the catalog, track progress on
MyAnimeList, follow friends’ public activity, and read title reviews and interest stacks in the app. It is
built with SwiftUI and talks directly to public APIs — there is no backend, account system, or database of
its own.

## Features

- **Anime and Manga lists** — status groups, search, sorting, pagination, swipe-to-update progress, swipe to
  remove, and a full editor for scores, repeat counts, dates, notes and custom lists.
- **Discover** — seasonal and ranked shelves, per-kind search, and genre, theme, studio and producer facets.
- **Title pages** — summary, metadata, relations, characters, recommendations, trailer, theme songs, reviews,
  interest stacks, and friends’ list activity. Tapping a poster shows it full screen. Characters open their own
  profile, and their voice actors open a page of their roles and staff credits.
- **Friends feed** — public updates from MyAnimeList friends, older pages, and native friend profiles with
  statistics, favorites and recent activity.
- **Profile** — account statistics, public favorites, custom lists, and a share link to the MyAnimeList profile.
- **Settings** — accent color, preferred title language, in-app link handling, a post-completion score prompt,
  preferred launch screen, iOS 26 tab-bar behavior, cache clearing, per-kind control over what a title page
  shows, plus About AniLedger and sign out.

## Requirements

- iPhone or iPad running iOS 17 or newer.
- Xcode 26 and the iOS 26 SDK to build from source.
- A MyAnimeList API application with the redirect URL `org.aniledger.ios://oauth` for sign-in.

## Data sources

| Source | Used for |
| --- | --- |
| MyAnimeList | OAuth sign-in, private lists and list edits |
| Tenrai | Preferred catalog source for search, rankings, details, reviews and stacks |
| Jikan Edge | Catalog fallback and public friends, favorites, statistics and activity |
| Device storage | Keychain tokens, list and feed snapshots, cached images and responses, preferences |

## Documentation

- [iOS setup, features and release guide](ios/README.md)
- [Architecture and API analysis](ARCHITECTURE.md)
- [iOS releases](https://github.com/jacobxhoang/aniledger/releases)

## Repository layout

```text
ios/
  AniLedger/          SwiftUI app sources and assets
  AniLedgerTests/     Swift Testing suites for decoding, titles, dates, store sync and OAuth callbacks
  AniLedger.xcodeproj Xcode project and shared scheme
  README.md           Setup, feature, settings and release guide
.github/workflows/    Build, format, test and release workflow
ARCHITECTURE.md       Project structure, API inventory, caching and risk analysis
```
