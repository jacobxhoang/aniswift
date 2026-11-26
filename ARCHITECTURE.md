# Aniswift — Project and API Analysis

Static analysis of the repository at commit `45c6128` (2026-11-25), plus read-only probes of the three live
APIs. Documentation was revised on 2026-11-25 for the settings layer, the preferred-title-language behaviour and
the current CI workflow, and again for the injected API client, the persisted-snapshot writer, the privacy
manifest and tag-driven releases. Nothing was compiled or run: there is no macOS/Xcode in this environment, so
build behaviour is unverified.

## 1. At a glance

Aniswift is a native SwiftUI anime and manga tracker for iPhone and iPad (iOS 17+ deployment target, built with
Xcode 26). It signs in to MyAnimeList with OAuth, keeps the user's anime/manga lists in sync, browses a catalog,
and follows friends' public activity. A settings layer controls the accent color, display language, link
handling, launch tab, tab-bar behavior, cache clearing and which groups appear on a title page. There is no
backend and no database: the app talks directly to three third-party HTTP APIs and keeps state on the device.
`AniswiftTests` holds Swift Testing suites for the shared decoder, title parsing, the activity-date heuristics,
stack-link parsing, the store's list sync and the OAuth callback; there are no UI or network tests.

The repository used to contain a web app and a Cloudflare Worker (`web/*`, `worker.js`, `package.json`, Render
configs). Those were deleted in `5fe096a "Retire the web app and remove review thumbs-up"` and
`13b061f "Remove retired Render deployment files"`. Today the repository is iOS-only.

## 2. Repository and build configuration

| Item | Value |
| --- | --- |
| Xcode project | `ios/Aniswift.xcodeproj` (`objectVersion = 56`), shared scheme **Aniswift** |
| Bundle identifier | `org.aniswift.ios` |
| Deployment target | iOS 17.0 (device family 1,2: iPhone and iPad) |
| Swift | 5.0; Liquid Glass and tab-bar-minimize paths guarded by `#available(iOS 26.0, *)` |
| Version | `MARKETING_VERSION = 1.0`, `CURRENT_PROJECT_VERSION = 1` |
| Dependencies | **Kingfisher 8.12.0** (images), pinned `exactVersion`, via Swift Package Manager |
| Tests | `AniswiftTests` unit-test bundle, Swift Testing, hosted by the app target; six suites, no UI tests |
| Privacy | `ios/Aniswift/PrivacyInfo.xcprivacy`: no tracking, no developer-collected data, UserDefaults and file timestamps |
| Formatting | `swift-format` from the Xcode 26 toolchain against the repository's `.swift-format` (120 columns, 4 spaces, existing line breaks respected); CI lints only files a change touches |
| URL scheme | `org.aniswift.ios` (OAuth callback `org.aniswift.ios://oauth`) |
| Info.plist | placeholder key `AniswiftMALClientID` (empty in the repo), portrait + landscape orientations |
| Assets | App icon |
| Preferences | `UserDefaults.standard`, all keys prefixed `aniswift.settings.`; app-wide, not per account |
| CI jobs | `format`, `test`, `ipa`, `release` in `.github/workflows/ios.yml`; one build per push, releases on `ios-v*` tags |

## 3. File map

| Path | Lines | Contents |
| --- | ---: | --- |
| `README.md` | 74 | Product overview, release channels, requirements, data sources, documentation links, repository layout |
| `ios/README.md` | 324 | Simulator/device setup, feature walkthrough, settings reference, data sources, MAL OAuth registration, CI secrets, nightly and tagged releases, development tools, manual verification checklist |
| `ARCHITECTURE.md` | 525 | This analysis: structure, APIs, state, caching, settings, CI and risks |
| `ios/Aniswift/API.swift` | 1328 | `APIError`, `Page` (with the provider's total), `MALCallback` redirect validation, Keychain-backed `MALSession`, redirect-blocking `MALTransport`, `SessionKeychain`, the `APIClient` protocol the store runs on (including the client ID it reads from the bundle), the `API` client (OAuth, lists, catalog cache with saved title pages, batched English titles with the remembered `TitleNameCache`, title lookup gate, private request queue), the AniList client (implicit-grant sign-in, the client ID the build ships, `AniListCallback`, `AniListSession`, `AniListEntry` and its Keychain), title-page section requests, catalog decoding helpers, `ASWebAuthenticationSession` wrappers |
| `ios/Aniswift/Models.swift` | 718 | `Kind` (its statuses and its media formats, which the two kinds do not share), `statusLabel`, tolerant `Fields` decoder, `CatalogFreshness`, `TitleLanguage`, `publicURL`, `AiringSlot` (the weekly slot an airing anime takes) and `AiringProgress` (which episode comes next and how many aired, from the slot, the premiere and the announced length), `Title` (with `displayName(for:)`), list models, custom-list models, `Account`, `Friend`, `FriendUpdate`, `TitleReview` (reading both providers' key shapes), interest stacks, `StackLink` (stack URLs inside a description), navigation route types |
| `ios/Aniswift/Store.swift` | 992 | `@MainActor` `ObservableObject`: account lifecycle, list sync with revision guards and reported failures (plus an `entries` index, so a poster tile reads its saved row in one step), custom-list organisation, friend feed batching (twelve friends per group, then list pages, until the page holds 30 rows), a friend's public list read in batches of pages (`FriendListBatch`), `resolveNames(in:)` (the English titles of one page, batched per kind) and `named(_:)`, `openFeed()` (a saved page older than ten minutes is refreshed on open) and paging, `PublicDataStatus` and public-refresh backoff, profile cache (statistics, favorites, favorite characters and people), activity-date heuristics (reusing one formatter per format), `plainMessage` (one plain sentence for every failure) |
| `ios/Aniswift/Persistence.swift` | 230 | `SnapshotWriter` (one serial queue for every snapshot file), `PublicDataStatus`, `SavedList`, `ListCache`, `FriendHistoryCursor` and `advancedHistoryCursors`, `FriendFeedCache`, `TitleNameCache` (the English titles resolved so far), profile statistics and favorites models (with the favorite characters and people) and `ProfileCache` |
| `ios/Aniswift/AniswiftApp.swift` | 1782 | App entry, five-tab root (iOS 26 `Tab` API with legacy `tabItem` fallback), launch-tab selection, accent tint and open-URL handling, navigation destinations, palette/layout constants (three edge tokens, the two airing states of a list row and a tile press style), `Haptics`, shared components (`LedgerShelf`, `LedgerViewAll`, `Art`, `PreferredTitle` (which reads the remembered name before it asks for one), `CoverTile` (one VoiceOver row, score named, pressed through `LedgerTileButtonStyle`), `Rail` (a poster width that follows Dynamic Type), `TitleRow`, `SignInButton`, `SavedDataNote` and `LedgerProblem` (the one notice panel and every retry, behind `ledgerNoticePanel`), one round `ledgerGlassCircle` control for a button that floats over a picture), `AccountScreen` (whose friends, days and favorite shelves follow the Profile toggles, and whose friends read as round portraits with the handle under them), `FriendProfileScreen`, `FriendMediaListScreen` (which reads the list to its end and counts the rows it holds), `AboutScreen` |
| `ios/Aniswift/SettingsScreen.swift` | 768 | `AccentChoice`, `SettingKey`, `DetailSection` (and its `all` list, the sections switch included), `DetailPreferences` (the Details Page toggles for one kind, read once), `ProfileSection` and `ProfilePreferences` (the Profile page toggles, read once), `SettingsScreen` (including the AniList section, then About, then sign out, every row drawn by `SettingsRow` as its title alone), `BehaviorSettingsScreen`, `DetailsSettingsScreen` (with the switch for everything below a summary), `ProfileSettingsScreen` (the appearance switches), `HeaderSettingsScreen`, `InfoSettingsScreen`, `AniListListsScreen` (the read-only lists), `PreferenceToggle`, `CacheRow`, settings rows/icons, `InAppBrowser` |
| `ios/Aniswift/CatalogScreens.swift` | 1881 | List status header, `ListSort` / `ListDetailFilter` / `ListFilter` (the order and the chips, remembered per kind, with the format chips taken from the kind itself), `ListFilterSheet` (the sort, its direction, status, format, entry-detail and year chips), `FilterChip` (a chosen chip says so with a checkmark), `ListsScreen` (with an inline retry when a kind's sync failed, a page-level empty state that offers the catalog and one that clears the filters), Discover shelves with a media switch under the search bar + `PosterShelf` (a poster width that follows Dynamic Type, one spoken tile) /`DiscoverScreen` (a page-level empty state when no shelf loaded), `CatalogFacet*`, `PosterResults` (a search that finds nothing links to MyAnimeList's own), `CatalogBrowser` (mode, season and year in one toolbar menu, an empty result offering the search cleared or the top rated shelf), `FriendsScreen`, `NextPageIndicator` (which retires itself when a page does not advance), `SearchResultCard` (a poster with its text capped at the poster's height, so a long summary cuts off), list/Discover/feed skeleton loaders |
| `ios/Aniswift/TitleScreen.swift` | 2368 | Title detail fan-out and layout, the next-episode countdown an airing anime draws under its header, `DetailPreferences` (the Details Page toggles, read once per kind), `TitleFacts` (the payload's studios, authors, genres, themes and serializations, decoded once), collapsible summary, details-page preference gating (one switch hides every section under the summary, and each hidden section is never requested), a failed section that says so and retries in place (reviews, characters, recommendations, stacks), full-screen poster (double tap or pinch to zoom, a white 44-point glass X where a back button would sit, and a retry when it cannot load), stack shelf and stack detail (with `StackSummary`, which makes the stack links in a description tappable), list controls, friends' activity (bounded friend scan), reviews shelf and reader, `FlowLayout`, `ListEditor` (full and quick modes) |
| `ios/Aniswift/CharacterScreen.swift` | 753 | `CharacterReference`, `PersonReference` (with the name as the provider writes it, for a manga header), `CastMember` (prefers Japanese voice actor, keeps their person id), `CastCard`, `CharactersScreen` (grid/list toggle), `CharacterScreen`, `PersonScreen` (voiced roles + anime/manga staff credits named in one batched request per kind, opened by a voice actor or a mangaka), `PersonRole`, `PersonCredit`, `CharacterVoice`, `PortraitCard`, `displayPersonName` |
| `ios/AniswiftTests/DecodingTests.swift` | 47 | `Fields` decoder and fallback-key tests |
| `ios/AniswiftTests/TitleTests.swift` | 76 | Title parsing, naming and sparse-title tests |
| `ios/AniswiftTests/ActivityDateTests.swift` | 47 | Activity-date parsing heuristics |
| `ios/AniswiftTests/StoreTests.swift` | 347 | A stub `APIClient` plus list-sync, optimistic-edit, failure-reporting, feed-cursor, friend-list batch and English-title batching tests |
| `ios/AniswiftTests/CallbackTests.swift` | 52 | `MALCallback` redirect validation: scheme, host, path, fragment, state and code |
| `ios/AniswiftTests/StackLinkTests.swift` | 59 | `StackLink` stack-URL parsing and description segmentation |
| `ios/Aniswift/Info.plist` | 24 | Bundle keys, MAL client-ID placeholder, URL type, orientations |
| `ios/Aniswift/PrivacyInfo.xcprivacy` | 31 | Privacy manifest: no tracking, no collected data types, UserDefaults and file-timestamp reasons |
| `ios/build-signed.sh` | 83 | Ad Hoc IPA export: temporary keychain, profile validation, manual signing, `release-testing` export |
| `.github/workflows/ios.yml` | 375 | Format check (skipping the unformatted files, reported as warnings), unit tests, optional client-ID injection, build-number stamping, unsigned/signed IPA build, tagged release, rolling nightly prerelease |
| `.gitignore` | 3 | `.env`, `.env.*`, `artifacts/` |

## 4. Architecture

```
AniswiftApp (@main)
 └ TabView: Anime | Manga | Discover | Feed | Profile
    each tab = NavigationStack + navigationDestination for
    Title, Friend, CharacterReference, PersonReference, CatalogFacet and
    route types (stacks, stack lists, collection grids, characters, reviews,
    friend lists, catalog browser/results, custom lists)
    Pushes that reach titles, friends, characters or facets use value routes;
    mixing destination closures with value links makes the next screen appear
    beneath the pushed one.
 └ .environmentObject(Store)
 └ @AppStorage accent / lastTab / tabBarBehavior

Views (ListsScreen, DiscoverScreen, FriendsScreen, AccountScreen,
       TitleScreen, CharacterScreen, SettingsScreen, ListEditor, …)
   │  read published Store state, call Store methods, use API for catalog reads
   │  read preferences with @AppStorage so open screens update live
   ▼
Store (@MainActor ObservableObject)
   │  account, lists, organisation, friends/activity, profile cache, messages
   ▼
API (@MainActor)
   ├── MyAnimeList v2  (authenticated: identity, lists, writes)
   ├── Tenrai         (catalog of record, stacks, reviews, Jikan-v4-shaped)
   └── Jikan Edge     (public user data, catalog fallback)
```

State ownership:

- **Keychain** — the MyAnimeList session (client ID, access token, refresh token, expiry).
- **Caches directory** — list snapshot, friends-feed snapshot, public profile cache and saved title pages. All
  written with `.completeFileProtectionUntilFirstUserAuthentication`, off the main actor through `SnapshotWriter`.
- **UserDefaults** — settings (`aniswift.settings.*`), per-account custom lists and hidden titles, legacy saved
  favorites.
- **Kingfisher** — poster/avatar memory (1 hour) and disk (30 days, 500 MB) caches; images are downsampled to the
  size they are drawn at.
- **In-memory** — 5-minute catalog cache (1 minute for `users/*`), in-flight request de-duplication, title-lookup
  coalescing, view-local state. Settings → Clear Cache drops this catalog cache along with the image and URL
  caches.

## 5. External APIs

| Provider | Base URL | Role |
| --- | --- | --- |
| MyAnimeList v2 | `https://api.myanimelist.net/v2` (OAuth: `https://myanimelist.net/v1/oauth2`) | Sign-in, identity, private lists, list edits |
| Tenrai | `https://api.tenrai.org/v1` | Preferred catalog: search, seasons, rankings, details, relations, cast, reviews, themes, genres, stacks |
| Jikan Edge | `https://jikan.lucashdo.com/v1` | **All** `users/*` data (statistics, favorites, friends, activity, public lists) and catalog fallback |
| AniList | `https://graphql.anilist.co` (OAuth: `https://anilist.co/api/v2/oauth/authorize`) | Settings → AniList: sign-in and a **read-only** view of the account's lists |

Schema differences, confirmed with live read-only requests:

- **Tenrai** is Jikan-v4 compatible and uses **snake_case**: `data.mal_id`, `title_english`, `titles[]`,
  `images.jpg.large_image_url`, `pagination.has_next_page`, reviews with `mal_id`/`review`/`is_spoiler`/`tags`/`user` or Jikan Edge's `reviewId`/`reviewText`/`isSpoiler`/`tag`/`username`/`imageUrl`,
  `/external` = `[{name,url}]`, `/seasons/now` and `/top/anime` shaped like Jikan v4.
- **Jikan Edge** uses **camelCase** and wraps responses in `{data, meta}` with
  `meta = {cached, stale, refreshFailed, fetchedAt}`. Public list rows are
  `{malId, title, imageUrl, progress, score, status, total, updatedAt, startedAt, finishedAt, mediaType, username}`
  with `meta.pagination = {page, limit, count, total, hasNextPage}`; statistics are
  `data.anime.{totalEntries, watching, completed, onHold, dropped, planToWatch, daysWatched, episodesWatched, meanScore}`
  and `data.manga.{…, chaptersRead, daysRead, volumesRead}`; `userupdates` is
  `data.anime[] = {date, status, score, progress, total, entry:{malId, title, imageUrl}}`.
- **Tenrai does not serve user profiles.** `/v1/users/{name}/{statistics,favorites,friends,userupdates,animelist}`
  answers `404 ROUTE_NOT_FOUND` with “User profile endpoints (/users) are not part of this API”. Public user data
  has no cross-provider fallback today.
- `api.myanimelist.net/v2` answers **403 `forbidden` without a Bearer token**, so every MAL call in this app is
  authenticated; no public catalog data is read from MAL directly.

Applications reconcile these schemas through `Fields` (section 6.3).

## 6. Endpoint inventory

### 6.1 MyAnimeList (authenticated, serialized)

| Request | Purpose | Notes |
| --- | --- | --- |
| `POST /oauth2/token` | code exchange and refresh-token rotation | form-encoded, `client_id` on every call |
| `GET /users/@me?fields=id,name,picture` | account identity after launch and sign-in | |
| `GET /users/@me/animeΔlist`, `/mangaΔlist` (`Δlist` = `list`) | list pages | `fields=list_status{…},…`, `limit=100`, `offset=(page-1)*100`, `sort=list_updated_at`, `nsfw=true` |
| `GET /{anime,manga}/{id}?fields=my_list_status{…}` | single entry for the editor | |
| `PUT /{kind}/{id}/my_list_status` | create/update entry | form: `status`, `score`, `num_watched_episodes` or `num_chapters_read`, optional `num_times_rewatched`/`num_times_reread`, `start_date`, `finish_date`, `comments` |
| `DELETE /{kind}/{id}/my_list_status` | remove entry | |
| `GET /anime/suggestions?limit=24&fields=…` | none: the rail it fed was removed with `HomeScreen` | |

Field sets are assembled per kind in `API.titleFields(_:)` and `API.statusFields(_:)`; `ListDetails.changes(from:)`
sends only fields the user actually changed.

### 6.2 Catalog (Tenrai first, Jikan Edge fallback; `users/*` goes to Jikan Edge only)

| Path | Consumer |
| --- | --- |
| `seasons/now`, `seasons/upcoming`, `seasons/{year}/{season}` | Discover, Browse catalog |
| `top/anime`, `top/manga` with `filter=airing\|upcoming\|bypopularity\|publishing`, `type=movie\|manhwa`, `order_by`, `sort`, `nulls`, `page` | Discover shelves, Browse |
| `{anime,manga}?q=&page=` | search |
| `{anime,manga}?ids=…&limit=…` | batch English names for friend-feed rows (50 ids per request) |
| `{anime,manga}?genres=<id>` / `?producers=<id>` (+ `order_by/sort/nulls`, `q`) | genre, theme, studio and producer screens |
| `genres/{anime,manga}?filter=genres\|themes`, `producers?q=` | facet name → MAL id resolution |
| `{kind}/{id}/recommendations` | the title page's “Recommended” shelf |
| `{anime,manga}/{id}` | single-title lookup used to fill English names and missing posters |
| `{anime,manga}/{id}/full` | the whole title page in one payload: details, summary, relation groups and theme songs |
| `{anime,manga}/{id}/characters` | cast; main roles sorted first |
| `{anime,manga}/{id}/recommendations` | recommended shelf |
| `{anime,manga}/{id}/reviews?page=&spoilers=true&preliminary=true` | review shelf/list/reader |
| `{anime,manga}/{id}/stacks?page=&sfw=false&sfw-strict=false` | interest stacks that contain the title (25/page); Tenrai is the only source that serves it, so the client retries it rather than falling back, and it asks for adult stacks explicitly, which the catalog otherwise leaves out |
| `stacks/{id}?sfw=false&sfw-strict=false` | stack description, author, badges and entries, adult entries included. A stack whose titles are all adult is not indexed at all: the title page and the stack page offer that one on MyAnimeList |
| `characters/{id}/full` | character biography, voice actors, appearances |
| `users/{name}/statistics` | profile statistics |
| `users/{name}/favorites` | favorite anime and manga |
| `users/{name}/friends` | friend list for the feed |
| `users/{name}/userupdates` | recent public activity |
| `users/{name}/{anime,manga}list?page=&limit=` | public lists (default 50/page; friend-entry scan uses 300/page for up to 10 pages) |

### 6.3 Field reconciliation

`Fields` decodes any JSON object into a dynamic-keyed container and exposes
`read<T: Decodable>(_ names: String...)` / `string(_ names: String...)` that try several keys in order (`try?`).
On top of that:

- `Title` reads the id from `mal_id | malId | id`; the English title from
  `title_english | titleEnglish | englishTitle | english_title | alternative_titles.en | titles[type=english]`;
  romaji from `title_romaji | … | titles[type=romaji] | title | name`; score from `score | mean`;
  count from `episodes | chapters | total | num_episodes | num_chapters`; artwork from
  `images.jpg.large_image_url | images.webp.… | images.large | main_picture | imageUrl | image | avatarUrl | avatar | picture`.
- `includesEnglishTitleField` marks rows as “sparse”; sparse rows without an English title set `needsTitleLookup`.
  Names are resolved in batches before a screen draws its page: `Store.resolveNames(in:)` groups the sparse titles
  by kind and asks `API.titleNames`, one Tenrai `ids` request per 50 titles with three chunks in flight, for the
  feed, the friend's list, the favourites rails of both profiles and a person's credits. A row still sparse after
  that, and every lone row in `PreferredTitle`, falls back to `API.resolveTitle`: one detail request per title,
  behind a 6-slot gate and one shared `Task` per id. `API` remembers every answer — the name, or the fact that the
  batch answered there is none — in `TitleNameCache`, so a title is asked about once per install instead of once
  per screen or launch. A person page passes `knownName`/`nameSettled` from its own batch, so a mangaka with 26
  credits costs one request instead of 26.
- `Title.displayName(for:)` is the single display rule for the stored language preference. It returns the
  original (romaji) name for `Romaji`, the English name for `English`, and falls back to whichever exists.
  `PreferredTitle`, list rows and sorting, title headers, interest-stack entries, review headers and editor
  prompts all use it, so a language change does not need per-screen conditions.
- A title page decodes its payload once into a `TitleFacts` value (`studios`, `producers`, `genres`, `themes`,
  `authors`, `serializations`), so the header and the information groups do not decode the same fields again on
  every body pass; the first paint from the cache decodes it there instead. `activityDate` reuses one formatter
  per format rather than allocating an ISO 8601 and a date formatter for every row it parses.
- The same multi-key pattern applies to `FriendUpdate` (`progress | episodesWatched | chaptersRead | …`),
  `ProfileStats`/`ProfileMediaStats` (`totalEntries | total_entries`, `onHold | on_hold`, …), `TitleReview`,
  `ListEntry`, `InterestStack` and `StackEntry`.

## 7. Authentication and session flow

1. **Client ID**: Info.plist `AniswiftMALClientID`, which CI injects from the `MAL_IOS_CLIENT_ID` secret. The app
   has no field for it: nothing is typed on the device, a build signs in with the ID it was built with, and a build
   without one says so from `SignInButton` instead of asking for it. The ID is checked as `^[A-Za-z0-9]{32}$`.
2. **PKCE**: 32 bytes from `SecRandomCopyBytes`, base64url-unpadded, used as `code_verifier` **and** `code_challenge`
   with `code_challenge_method=plain`; a second random value is the OAuth `state`.
3. **Authorize**: `ASWebAuthenticationSession` on the key window. Session, `code`, and redirect are validated
   strictly: scheme `org.aniswift.ios`, host `oauth`, empty path, no user/password/port/fragment, exactly one
   `state` equal to the generated value, exactly one non-empty `code`.
4. **Exchange**: `POST /oauth2/token` with `grant_type=authorization_code`, `code`, `redirect_uri`,
   `code_verifier`, `client_id`. Then `GET /users/@me` with the new access token to read the account.
5. **Persist**: session JSON (client ID, access/refresh token, expiry) in the Keychain
   (`kSecClassGenericPassword`, service `org.aniswift.ios`, account `mal-native-session`,
   `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`). `sessionGeneration` rotates so stale work is dropped.
6. **Refresh**: before a private request when expiry is under 60 seconds, or after a 401 (then the request is retried
   once). A 400/401 from the refresh endpoint signs the user out with “Your MyAnimeList session expired.”
7. **Transport hardening**: MAL uses an **ephemeral** `URLSession` with a delegate that cancels every HTTP redirect,
   cookies disabled, 25-second timeout, JSON `Accept`. Private calls are chained through one queue so refresh-token
   rotation and list edits stay ordered.
8. **Sign-out**: deletes the Keychain item, bumps `sessionGeneration`, clears account state, list snapshot and
   friends-feed cache. Custom lists and settings remain on the device.
9. **AniList** is a second, read-only sign-in: its implicit grant opens the same `ASWebAuthenticationSession` on
   `anilist.co/api/v2/oauth/authorize?client_id=…&response_type=token`, and the token arrives in the redirect's
   **fragment** (`#access_token=…&token_type=Bearer&expires_in=…`), which `AniListCallback` reads apart from the
   MyAnimeList query. The client ID is the one the build ships in Info.plist (`AniswiftAniListClientID`, `58162`);
   the app has no field for it, so Connect uses the ID it was built with. The session (token, expiry, account id
   and name) is a Keychain
   item under account `anilist-session`. Nothing is written back to AniList: `MediaListCollection` is read through
   its GraphQL API and drawn in Settings → AniList. Both directions use AniList's 100-point score: a change is sent
   as `scoreRaw` (a MyAnimeList 8 is 80) and the lists are read with `score(format: POINT_100)`, because the plain
   `score` argument is taken in the account's own format and a POINT_10 account read the 80 as a full 10/10.

## 8. Caching and concurrency

| Layer | Behaviour |
| --- | --- |
| Catalog memory cache | 5-minute TTL keyed by resolved URL, 1 minute for `users/*` lists, friends and activity so user data refreshes on open; capped at 160 entries with oldest-first eviction; `refresh: true` bypasses reads but still writes. A title page also seeds `record` from `cachedDetail` so a revisit paints its summary and sections before the network answers. `hasCachedCatalog` lets Settings report catalog-only caches; `clearCatalogCache()` drops the dictionary and the saved detail files. |
| Saved title pages | `Caches/AniswiftDetailCache/<kind>-<id>-full.json`: the raw `anime|manga/{id}/full` body written after a successful catalog read (< 2 MB). Used only when the live request fails and nothing is in memory: the page paints the saved payload under a “Showing saved data” note with Retry, instead of an error or an empty screen. |
| In-flight de-duplication | one shared `Task` per catalog URL |
| Title lookups | one `Task` per `Title.id`; a 6-slot `CheckedContinuation` gate limits concurrent Tenrai detail fetches |
| List snapshot | `Aniswift-lists-v1.json`: account + `[Kind: SavedList(items, page, more, needsReconciliation)]` |
| Friends feed | `Aniswift-friends-feed-v1.json`: account ID, friends, activity, checked count, history cursors, page |
| English titles | `Aniswift-title-names-v1.json`: `kind-id` → English name for rows a provider sends without one, plus the ids a batch answered as having none. Capped at 4000 names, written once per burst of resolutions, and dropped by Clear Cache. |
| Public profiles | `Aniswift-profiles-v1.json`: stats, favorites, favorite characters and people per user with **15-minute** freshness |
| Saved-data state | Per-profile and feed `PublicDataStatus` (stale flag, last failure, snapshot time). Public refreshes honour Jikan Edge `meta.stale`/`refreshFailed`, keep the previous snapshot on screen, and back off 15/30/60 s (three automatic attempts, reset by pull-to-refresh or Retry). |
| Custom lists | UserDefaults `aniswift.organization.v1.<accountID>` |
| Settings | UserDefaults `aniswift.settings.*`; Clear Cache does not touch them |
| Images | Kingfisher memory + disk, with `DownsamplingImageProcessor` sized from `GeometryReader` and `displayScale`; fades disabled under Reduce Motion; the friends feed and both list screens prefetch their first 30 posters through `View.prefetchingPosters(_:limit:url:)`, keyed on the row ids |

Concurrency patterns:

- The feed's activity and list pages are fetched and decoded off the main actor (`API.friendUpdates`,
  `API.friendListPage`): `Fields` wraps a decoder container and cannot leave the thread that decoded it, so the
  rows are built there and only values come back. Six friends are then six requests in flight instead of six
  tasks waiting to parse on the main thread, and the decoded rows are cached for the same one-minute lifetime.
- Discover loads 10 shelves in batches of 3 task groups; the friend feed walks twelve friends at a time with six
  concurrent `publicUpdates` calls, in up to four groups per page, and then fills from four list pages at a time
  (twice) while the page is still thin, until it holds 30 rows or has walked every page it can reach — one
  friend answers with only a handful of updates, so a page built from one group looked empty; the title screen fans
  out up to 4 requests concurrently (`/full` and reviews always; characters and recommendations only when those
  sections are enabled), and the stacks follow the payload alone: they are the one section only the catalog source
  serves, and asked beside it they lost the turn. A failed stacks request is asked again once before the shelf
  reports a failure; friends'-activity scanning looks up 6 friends per batch concurrently.
- List sync re-fetches the whole loaded page range as a unit. A `listRevisions[kind]` counter aborts a sync if an
  edit lands mid-flight and sets `needsReconciliation` so the next page load re-syncs. Edits are applied
  optimistically.
- Every account-scoped mutation checks `accountGeneration`, so a sign-out cannot write into a new session.
- A friend-feed refresh resets `friendFeedPage` to 0 before incrementing, so the persisted page counter restarts
  with the refreshed snapshot instead of drifting upward across pull-to-refreshes.

## 9. Feature map

| Tab / screen | Reads | Writes |
| --- | --- | --- |
| Anime, Manga (`ListsScreen`) | cached list grouped by status (on-hold/dropped collapsed), search across loaded entries, and one **Sort and Filter** sheet — the order (title, recently updated, my rating, my progress, average score) with its direction spelled out, then status, format, entry-detail and year chips, the formats being the kind's own (TV and movies for anime, manga and novels for manga) — remembered per kind; a row for a title still on the air adds when its next episode is due, in amber while an aired episode is unwatched and green once the reader is caught up; pagination; the empty state appears only for a loaded, empty snapshot, and a filter or search that finds nothing offers the way out | swipe +1 episode/chapter, swipe remove, full editor |
| Discover | 10 shelves, per-kind search, genre/theme/studio/producer facets, catalog browser with season/year pickers | — |
| Feed | friends list, per-friend `userupdates` (anime + manga), older pages via persisted cursors, English-name backfill; keeps the saved feed with a “Showing saved data” note and retry when Jikan Edge fails or reports stale data | — |
| Profile | account, public statistics, favorites (anime, manga, characters and people), friends, custom lists, About/version; saved snapshot stays visible with a note and retry when the public data cannot be refreshed; the appearance toggles decide which of those the page draws | sign in/out |
| Title | detail, relations, cast, recommendations, trailer, themes, interest stacks, reviews, friends' activity; an anime still on the air names its next episode in a band under the header, counting down to the weekly slot its payload carries (`AiringSlot`, in Japan's zone); adult stacks are asked for, and one the catalog does not index opens on MyAnimeList from the page; tapping the header poster opens it full screen, and a manga's authors open their own page; header, content and information groups follow the Details Page settings, so a hidden section is never requested and one switch hides everything below the summary | add/edit/remove entry, mark completed, quick status/progress/score, full editor (rewatch count, dates, notes ≤ 4000 bytes, custom lists, hide), share, open on MAL |
| Character | biography, member favorites, Japanese-preferred voice actors (each opening their own page), anime/manga appearances | — |
| Voice actor or mangaka (`PersonScreen`) | `people/{id}/full`: portrait, alternate names, birthday, member favorites, biography, voiced roles (main parts first, 12 then all) and anime/manga staff credits (8 then all); a role opens its character, a credit opens its title through `PreferredTitle`, which takes the credit's English name from one batched `titleNames` request per kind. Opened from a character's voice actors and from the authors a manga's header lists | — |
| Friend profile | stats header, list buttons only for non-empty lists, recent updates, favorites, pull-to-refresh | — |
| Friend's anime or manga list | `users/{name}/{kind}list` read to its end in batches of four 100-row pages, grouped by status (completed/on-hold/dropped collapsed), the loaded count against `meta.pagination.total` while it reads, a retry for the page that failed | — |
| Settings | `@AppStorage` preferences, cache sizes, version and service credits; the AniList session and its read-only lists | accent, language, link handling, score prompt, launch screen, tab bar, 34 detail toggles, 8 profile toggles, the AniList sign-in, cache clearing |

Design system: black canvas, forced dark scheme, shared `LedgerLayout` metrics, one `LedgerShelf` carousel for
every rail, one `LedgerViewAll` link across shelves, a configurable
tint (White default; eight other accent choices), Liquid Glass on iOS 26 with material/bordered fallbacks,
`ViewThatFits` and adaptive grids for accessibility sizes, empty states as page blocks or `ContentUnavailableView`,
`.sensoryFeedback` on controls plus success/error haptics, `SkeletonBlock` first-load placeholders on title pages,
lists, Discover and the feed, `plainMessage` for every failure sentence, VoiceOver labels and hints throughout,
and an in-app `SFSafariViewController` whose controls use the selected accent.

Three `Palette` edges carry every boundary instead of the 8–20% white each view used to pick: `hairline` (22%) for
posters, panels, capsules and dividers — the old 8–14% measured about 1.3:1 on the canvas — `border` (32%) for an
active or selected control, and `fill` (12%) behind a chip, which needs no boundary. A shelf tile presses through
`LedgerTileButtonStyle` (a 0.97 scale and a dim, no layout shift, none of it under Reduce Motion), reads as one
VoiceOver element with its score named out of ten, and its poster width follows Dynamic Type up to 1.4× through
`@ScaledMetric`, so text and artwork scale together. Any section that fails to load says so and retries in place —
the reviews shelf, characters, recommendations and interest stacks on a title page, and the poster viewer — instead
of vanishing or closing on a stray tap: the viewer zooms on a double tap while its glass X is the only dismiss.

The shell follows the platform: the five tabs become the iPadOS 18 sidebar (`sidebarAdaptable`) and can be
reordered; a poster's long press opens a peeking menu — progress, MyAnimeList and Share — over the poster itself;
a removal is a swipe and a six-second **Undo** bar rather than a question; an unsaved editor blocks the drag down
and asks before its X discards it; sign-out is a plain row, red being kept for actions that destroy something; an
empty state offers the step out of it (Refresh, Sync AniList, the catalog when a list is still empty); a search
field offers the six queries kept on the device (`searchRecents`); and every group heading is the app's own
`ListStatusHeader`. A list is ordered and narrowed in one sheet (`ListFilterSheet`): the sort in a menu, a round
control that turns it around, the direction spelled out under it, and chips that say they are on with a checkmark
as well as a fill — so the sheet reads in any accent and for a reader who cannot separate two greys — with every
choice remembered per kind and a Reset back to everything kept. Settings is a list of titles: a row says what it
opens or sets and nothing more, its sections are headings alone, and the screen that explains the app rather than
setting it — About — sits under AniList and above Sign Out. A failure is the same notice panel as a saved-data
note (`LedgerProblem`), with one sentence and one retry, so every screen reports the two conditions it can be in
with one look. A friend reads as a person rather than a poster: a round portrait with the hairline every picture
carries, and the handle under it at reading size; a favorite character or person keeps a poster's corners. A title
page's header draws a number only where it has a value, never an em dash under the
label. Thumbnails, the score sheet's star and the shelves' posters follow Dynamic Type, and `LedgerLayout` names
the corner scale — `rowRadius`, `posterRadius`, `panelRadius`, `sheetRadius` — which every view now uses. A
search that finds nothing offers its next step: MyAnimeList's own search, a cleared search field, or the top rated
shelf.

## 10. Settings and personalization

All preferences are stored in `UserDefaults.standard` under `aniswift.settings.*` and read with `@AppStorage`,
so a change updates open screens without a restart. The 34 Details Page toggles are the exception: a title page
reads them once into a `DetailPreferences` value per kind and refreshes it on `UserDefaults` changes, instead of
asking `UserDefaults` thirty-four times on every body pass. They are **device-wide**: switching MyAnimeList accounts or
signing out does not reset them, and they never sync.

| Preferences | Preference | Key | Default | Effect |
| --- | --- | --- | --- | --- |
| Accent Color | `accent` | `White` | `.tint` at the app root, controls, links, highlights and the in-app browser's controls. Choices: White, Blue, Red, Green, Brown, Cyan, Gray, Purple, Mint. The selection ring/checkmark animation is skipped under Reduce Motion. |
| Preferred Title Language | `titleLanguage` | `English` | Display-only name choice through `Title.displayName(for:)`; English falls back to Romaji and vice versa. Used by title pages, `PreferredTitle` tiles/rows, list sorting, stack entries, review headers/reader and editor prompts. List search matches either name. |
| Open Links In-App | `openLinksInApp` | `true` | `OpenURLAction` presents http(s) links in `SFSafariViewController`; if no foreground scene can present it, the action returns `.systemAction` so the link still opens. |
| Ask for Score After Watching an Anime | `askForScore` | `true` | In `ListEditor`, a transition to `completed` with rating 0 opens the score prompt; the editor skips entries already completed, and the prompt never opens from the score sheet itself. The title's Mark completed action asks whenever the update is completed and the entry still has no score. Anime only. |
| Enable Preferred Launch Screen | `preferredLaunch` | `false` | `AniswiftApp.init()` chooses `launchTab` instead of `lastTab` for the initial tab. |
| Preferred Screen | `launchTab` | `anime` | Anime, Manga, Discover, Feed or Profile. |
| Last Used Tab | `lastTab` | `anime` | Written whenever the selected tab changes; used when preferred launch is off. |
| Tab Bar Behavior | `tabBarBehavior` | `never` | iOS 26 only: `never` (always visible) or `onScrollDown` (`.tabBarMinimizeBehavior`). |

Details Page toggles use `aniswift.settings.details.<anime|manga>.<section>` and all default to `true`. There
are 18 anime keys and 15 manga keys (33 total):

| Group | Section keys | UI |
| --- | --- | --- |
| Sections | `sections` | One switch that hides everything under a title's summary — information, background, related titles, characters, recommendations, stacks, trailer, theme songs, friends' activity and reviews — and skips the requests those sections make |
| Header | `header.poster`, `header.score`, `header.rank`, `header.popularity`, `header.creators` | Poster, average score, MAL rank, popularity, studios (anime) / authors (manga) |
| Content | `characters`, `trailer`, `related`, `source`, `openings`, `endings`, `recommendations` | Character list, trailer, related titles, source, openings, endings, recommendations; trailer/openings/endings are anime-only and the manga screen omits them |
| Information | `info.series`, `info.alternatives`, `info.genres`, `info.themes`, `info.creators` | Series information, alternative titles, genres, themes, studios and producers (anime) / serialization (manga) |

`source` is rendered inside the Series Information block, so hiding Series Information also hides the source line.
The summary stays visible regardless of settings. “Show Sections Below Summary” hides everything under it —
background, interest stacks, friends' list activity and reviews included — and stops their requests; the
per-section toggles then change what it leaves visible.

Profile toggles use `aniswift.settings.profile.<section>`, default to `true`, and are read the same way through
`ProfilePreferences` (8 keys):

| Group | Section keys | UI |
| --- | --- | --- |
| Appearance | `friends`, `days`, `anime.statistics`, `manga.statistics`, `favorite.anime`, `favorite.manga`, `favorite.characters`, `favorite.people` | Friends shelf, days watched in the header, the anime and manga statistics, and the favorite anime, manga, characters and people shelves; the friends shelf is the only one that costs a request (`users/{name}/friends`) and it is skipped while hidden |

Clear Cache (`CacheRow`) clears `ImageCache` memory and disk, `URLCache.shared`, and `API.cached`. It does not
touch the Keychain session, list/feed/profile snapshot files, custom lists or any preference. The row shows the
combined image-disk and URL-cache size, or “Catalog responses cached” when only the in-memory catalog cache
remains. In-flight catalog requests are not cancelled, so a request that completes just after clearing can
repopulate an entry.

## 11. CI and release

`Build Aniswift IPA` runs on pushes to `main`, on tags matching `ios-v*`, on pull requests touching `ios/**` or
the workflow, and manually with a `signed` flag. A newer push of the same branch cancels the run it supersedes;
pull requests never publish.

1. `format` (macos-15) selects Xcode 26 and runs `swift-format lint --strict` on the Swift files changed against
   the pull-request base (or the push `before` SHA). It skips when there is no usable base, and it skips the files
   listed in `UNFORMATTED` (`TitleScreen`, `CatalogScreens`, `SettingsScreen`, `Store` and `API`), which predate the
   formatter and have never been formatted in bulk. It is advisory twice over: it is not in the `ipa` job's `needs`,
   and a finding is reported as a warning with the formatted copy of each file attached as the `swift-format`
   artifact, so the run itself stays green. Once the tree is formatted, `exit 1` at the end of the lint step and one
   entry in `needs` turn it into a gate.
2. `test` (macos-15) selects Xcode 26 and the newest available iPhone simulator, runs `xcodebuild test` for the
   `Aniswift` scheme (arm64, signing disabled) against the six suites in `AniswiftTests`, and uploads the
   `.xcresult` when the run fails. The Swift package cache is restored between runs.
3. `ipa` (macos-15) needs `test`. The test result is advisory until the repository variable `TESTS_GATE` is `on`;
   after that a failing suite blocks the IPA. The job builds **one** tree — the tip of the push, the tagged
   commit or the pull request — selects Xcode 26, injects `MAL_IOS_CLIENT_ID` into Info.plist for every build
   that is not a pull request after validating 32 alphanumerics, then archives unsigned
   (`CODE_SIGNING_ALLOWED=NO`) and zips `Payload/` into `Aniswift-Unsigned.ipa`. The `signed` path runs
   `ios/build-signed.sh`: temporary keychain, Ad Hoc profile validation (registered devices, no
   `get-task-allow`, explicit App ID), team/bundle derived from the profile, manual `Apple Distribution` signing,
   `release-testing` export.
4. `release` publishes the IPA on the `ios-v*` tag that triggered the run, idempotently uploading the asset if it
   is missing. A branch push publishes nothing.
5. `nightly` needs `ipa` and runs only for a push to `main`: it downloads `Aniswift-Unsigned.ipa`, renames it to
   `Aniswift-Nightly-Unsigned.ipa` and publishes it to one rolling prerelease tagged `nightly`, whose tag moves to
   the built commit on every run. The asset name never changes, so the download link is stable; the release notes
   list the commits since the previous nightly, read from the tag before it moves. Because `releases/latest` skips
   prereleases, the stable download stays the newest `ios-v*` tag. While `TESTS_GATE` is off a red suite still
   publishes a nightly — that is what the channel is for — and setting the gate stops it.

A build used to be produced for every first-parent commit in a push and published as a prerelease per commit.
That multiplied macOS runner minutes by the commit count and made the release list unreadable, so the matrix and
its `commits` job are gone: one push is one build, and a release is a tag.

## 12. Risks and gotchas

1. **Tests cover the model and the store, not the screens.** Six Swift Testing suites cover `Fields`, `Title`
   parsing, activity-date heuristics, stack-link parsing, the store's list sync and failure reporting, the
   friend-feed cursor bookkeeping and the OAuth callback validation; there are no UI or live-network tests. The
   test job is advisory until `TESTS_GATE=on`, and the format job is still not a dependency of the IPA job, so
   style regressions can ship.
2. **Two critical-path third-party proxies.** Tenrai serves the catalog; Jikan Edge serves every public user
   feature. Catalog has a Tenrai → Jikan Edge fallback; `users/*` has **none** (Tenrai rejects `/users/*` with
   `404 ROUTE_NOT_FOUND`), so the feed and profiles fail together if Jikan Edge is down. The app keeps the last
   profile snapshot and friends feed on screen with a “Showing saved data” note, surfaces
   `meta.stale`/`refreshFailed`, and retries with 15/30/60 s backoff, but no alternative provider for public user
   data exists.
3. **Three catalog endpoints have no caller.** Discover owns the seasonal and ranked rails (`seasons/now`,
   `seasons/upcoming`, `top/anime?filter=airing|upcoming`), so only `recommendations/anime`,
   `recommendations/manga` and `anime/suggestions` are unused. Reviving them means a real surface, not restoring
   the removed `HomeScreen`.
4. **Global serialization of private requests** (`API.privateQueue`) means a slow list refresh delays an edit.
   Intentional for token ordering, but it is the main latency coupling in the app.
5. **Pagination is inferred** for public data (`hasNextPage` → `pagination.total` → `rows.count == limit`); MAL lists
   assume 100/page. A friend's list is read at 100/page in batches of four pages, and the batch ends when a page
   reports no more or repeats rows it already answered, so a page that stops advancing cannot be asked for forever.
   `friendEntry` answers from one `userupdates` request.
6. **English titles for user lists.** Jikan Edge list and activity rows carry no English title. Every screen that
   draws a page of them resolves the names in batches of 50 through Tenrai's `{kind}?ids=` filter before it
   publishes the rows, and `API` remembers each answer — the name, or the fact that the title has none — in
   `Aniswift-title-names-v1.json`, so a second visit costs no request at all. A lone row still resolves through a
   detail request. The preferred-language setting affects display only, not what is fetched or stored.
7. **Date parsing is heuristic** (`Store.activityDate`): ISO8601, ISO8601 with fractional seconds, `yyyy-MM-dd`,
   `MMM d, yyyy`, `MMM d, h:mm a`, `MMM d`, then “today”/“yesterday”. `defaultDate = Date()` can assume the
   current year, and the “future date means last year” rollback only applies to year-less formats.
8. **Silent degradation.** Because almost every field read is `try?`, a provider schema change yields empty
   sections rather than an error, and “no data” is indistinguishable from “failed request”.
9. **Device-local state.** Custom lists, hidden titles, saved snapshots and every setting live on the device.
   Settings are app-wide rather than per account, survive sign-out and are not restored by MyAnimeList.
10. **Mixed session usage.** Catalog requests use `URLSession.shared` (cookies and HTTP cache shared across
    providers) while MAL uses an ephemeral, redirect-blocked session.
11. **`ListEntry.updated` falls back to the current time** when a provider omits `updated_at`, which can misorder
    the “recently updated” sort.
12. **Client ID is public in distributed builds.** The README states that a bundled ID is readable from an IPA;
    tokens stay in the Keychain.
13. **Xcode 26 is mandatory in CI** even for the iOS 17 target, so older runner images cannot build the app.
14. **No background refresh.** Data refreshes on view tasks, pull-to-refresh, the 5-minute title-detail TTL, the
    1-minute `users/*` TTL and the 15-minute profile freshness window only.
15. **The sections switch stops the requests, not the `/full` payload.** With “Show Sections Below Summary” off,
    a title page hides every section under the summary and skips the requests they make — characters,
    recommendations, reviews, stacks and the friends scan included — and one section's own toggle does the same
    for its request. The `/full` payload and the header toggles always run.
16. **Clear Cache does not cancel in-flight work.** `catalogRequests` is left intact, so a response that arrives
    after clearing can be cached (and its detail JSON re-written) again immediately. It also measures only
    image-disk and URL-cache bytes, not the in-memory catalog dictionary or the saved title pages.
17. **Snapshot writes leave the main actor.** Each successful `anime|manga/{id}[/full]` response, list page, feed
    page and profile refresh is encoded where the value lives and handed to `SnapshotWriter`, one serial utility
    queue that also orders a removal behind the writes before it. Encoding a large snapshot still costs the actor
    that holds it a millisecond or two, and the write is best-effort: a failed write leaves the previous snapshot.
18. **A failed feed page keeps its cursor.** `advancedHistoryCursors` consumes only the cursors whose page
    answered, so a Jikan Edge failure delays a friend's older pages instead of dropping them for the session.
    A page that cannot be read also sets `feedPageStalled`, which stops the feed asking for a page that will not
    arrive until the reader refreshes; a batch that answers with nothing this feed can show still advances the
    page counter, so pagination continues instead of stopping silently. A page that recent activity cannot fill is
    filled from those list pages before it is drawn, and `openFeed()` refreshes a saved page older than ten
    minutes, so a thin snapshot from an earlier run cannot keep the feed short for good.
19. **A title page scans a bounded set of friends.** Friends' list activity checks at most 18 friends per title
    page (`TitleScreen.friendScanLimit`), and each friend costs one `userupdates` request: the row shows their
    recent activity, not the whole list, so a friend who liked the title long ago is not in it. Every other friend
    is still reachable from the feed and their profile.
20. **The nightly asset is overwritten in place.** `Aniswift-Nightly-Unsigned.ipa` keeps its name so the download
    link is stable, which means a rebuild replaces it under the same URL: a cached or CDN copy can still hand out
    the previous nightly, and the build number in About is how two of them are told apart.
21. **Search is the system's field on each screen, so its placement decides when it shows.** The lists and Discover
    put a `.searchable` field in the navigation bar drawer in `.always` mode, Browse catalog uses the default
    drawer, and the facet screen's producer view uses the toolbar field on iOS 26 and the drawer below it. There
    is no one shared search control, and Discover carries its anime/manga switch in a segmented row above the
    results while a search is active, because a scope bar is not used.

## 13. How this analysis was produced

- Every Swift file, `Info.plist`, the Xcode project and scheme, both READMEs, `ios/build-signed.sh`, the workflow,
  `.swift-format` and `.gitignore` were read in full; the file map line counts come from `wc -l`.
- Settings were checked against their actual read sites: `@AppStorage` keys in `TitleScreen`, `AniswiftApp` and
  `SettingsScreen`, the title-language helper in `Models`, and the cache/`InAppBrowser` paths.
- Live APIs were called read-only (no authentication, no writes) to confirm provider split, response envelopes,
  JSON key casing and pagination fields:

  ```text
  api.tenrai.org/v1/anime/1                 200  Jikan-v4 snake_case payload
  api.tenrai.org/v1/top/anime               data[] + pagination.has_next_page
  api.tenrai.org/v1/anime/1/reviews         data[] with mal_id/review/is_spoiler/user
  api.tenrai.org/v1/anime/1/stacks          data[] + pagination (25/page)
  api.tenrai.org/v1/stacks/1                data{}
  api.tenrai.org/v1/genres/anime            data[]
  api.tenrai.org/v1/anime/1/external        [{name,url}]
  api.tenrai.org/v1/characters/1/full       data{}
  jikan.lucashdo.com/v1/anime/1             200  camelCase payload + meta
  jikan.lucashdo.com/v1/users/xinil/statistics   data.anime/… camelCase
  jikan.lucashdo.com/v1/users/xinil/userupdates  data.anime[] + meta.cached/stale/fetchedAt
  jikan.lucashdo.com/v1/users/xinil/animelist    data[] + meta.pagination.hasNextPage
  api.tenrai.org/v1/users/xinil/*           404  ROUTE_NOT_FOUND, user endpoints not offered
  api.myanimelist.net/v2/anime/1            403  forbidden without a Bearer token
  ```

- Not verified: compilation, SwiftUI rendering, Keychain/OAuth round-trip, settings persistence on device,
  signing and the CI workflow's actual runs.
