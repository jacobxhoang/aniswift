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
| `README.md` | 64 | Product overview, release channels, requirements, data sources, documentation links, repository layout |
| `ios/README.md` | 277 | Simulator/device setup, feature walkthrough, settings reference, data sources, MAL OAuth registration, CI secrets, nightly and tagged releases, development tools, manual verification checklist |
| `ARCHITECTURE.md` | 466 | This analysis: structure, APIs, state, caching, settings, CI and risks |
| `ios/Aniswift/API.swift` | 781 | `APIError`, `Page`, `MALCallback` redirect validation, Keychain-backed `MALSession`, redirect-blocking `MALTransport`, `SessionKeychain`, the `APIClient` protocol the store runs on (including the client ID it reads and writes), the `API` client (OAuth, lists, catalog cache with saved title pages, title lookup gate, private request queue), title-page section requests, catalog decoding helpers, `ASWebAuthenticationSession` wrapper |
| `ios/Aniswift/Models.swift` | 560 | `Kind`, `statusLabel`, tolerant `Fields` decoder, `CatalogFreshness`, `TitleLanguage`, `publicURL`, `Title` (with `displayName(for:)`), list models, custom-list models, `Account`, `Friend`, `FriendUpdate`, `TitleReview`, interest stacks, `StackLink` (stack URLs inside a description), navigation route types |
| `ios/Aniswift/Store.swift` | 931 | `@MainActor` `ObservableObject`: account lifecycle, list sync with revision guards and reported failures (plus an `entries` index, so a poster tile reads its saved row in one step), custom-list organisation, friend feed batching (twelve friends per group, then list pages, until the page holds 30 rows), `openFeed()` (a saved page older than ten minutes is refreshed on open) and paging, `PublicDataStatus` and public-refresh backoff, profile cache, activity-date heuristics (reusing one formatter per format), `plainMessage` (one plain sentence for every failure) |
| `ios/Aniswift/Persistence.swift` | 205 | `SnapshotWriter` (one serial queue for every snapshot file), `PublicDataStatus`, `SavedList`, `ListCache`, `FriendHistoryCursor` and `advancedHistoryCursors`, `FriendFeedCache`, profile statistics models and `ProfileCache` |
| `ios/Aniswift/AniswiftApp.swift` | 1522 | App entry, five-tab root (iOS 26 `Tab` API with legacy `tabItem` fallback), launch-tab selection, accent tint and open-URL handling, navigation destinations, palette/layout constants, `Haptics`, shared components (`LedgerShelf`, `LedgerViewAll`, `ledgerSearch`/`LedgerSearch` (a round glass search button that expands the field), `Art`, `PreferredTitle` (with a batch-resolved name), `CoverTile`, `Rail`, `TitleRow`, `SignInButton`, `SavedDataNote`), `AccountScreen`, `FriendProfileScreen`, `FriendMediaListScreen`, `AboutScreen` |
| `ios/Aniswift/SettingsScreen.swift` | 605 | `AccentChoice`, `SettingKey`, `DetailSection` (and its `all` list), `DetailPreferences` (the Details Page toggles for one kind, read once), `SettingsScreen` (including About, sign out and cache), `BehaviorSettingsScreen` (including the MyAnimeList client ID), `DetailsSettingsScreen`, `HeaderSettingsScreen`, `InfoSettingsScreen`, `PreferenceToggle`, `CacheRow`, settings rows/icons, `InAppBrowser` |
| `ios/Aniswift/CatalogScreens.swift` | 1335 | List status header, `ListsScreen` (with an inline retry when a kind's sync failed and a page-level empty state), Discover shelves with a media switch under the search bar + `PosterShelf`/`DiscoverScreen`, `CatalogFacet*`, `PosterResults`, `CatalogBrowser` (mode, season and year in one toolbar menu), `FriendsScreen`, `NextPageIndicator` (which retires itself when a page does not advance), `SearchResultCard`, list/Discover/feed skeleton loaders |
| `ios/Aniswift/TitleScreen.swift` | 2047 | Title detail fan-out and layout, `DetailPreferences` (the Details Page toggles, read once per kind), `TitleFacts` (the payload's studios, authors, genres, themes and serializations, decoded once), collapsible summary, details-page preference gating, full-screen poster, stack shelf and stack detail (with `StackSummary`, which makes the stack links in a description tappable), list controls, friends' activity (bounded friend scan), reviews list/reader (the card keeps the verdict and the date on separate lines), `FlowLayout`, `ListEditor` (full and quick modes) |
| `ios/Aniswift/CharacterScreen.swift` | 759 | `CharacterReference`, `PersonReference` (with the name as the provider writes it, for a manga header), `CastMember` (prefers Japanese voice actor, keeps their person id), `CastCard`, `CharactersScreen` (grid/list toggle), `CharacterScreen`, `PersonScreen` (voiced roles + anime/manga staff credits named in one batched request per kind, opened by a voice actor or a mangaka), `PersonRole`, `PersonCredit`, `CharacterVoice`, `PortraitCard`, `displayPersonName` |
| `ios/AniswiftTests/DecodingTests.swift` | 47 | `Fields` decoder and fallback-key tests |
| `ios/AniswiftTests/TitleTests.swift` | 76 | Title parsing, naming and sparse-title tests |
| `ios/AniswiftTests/ActivityDateTests.swift` | 47 | Activity-date parsing heuristics |
| `ios/AniswiftTests/StoreTests.swift` | 187 | A stub `APIClient` plus list-sync, optimistic-edit, failure-reporting and feed-cursor tests |
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
- **UserDefaults** — settings (`aniswift.settings.*`), per-account custom lists and hidden titles, the MAL
  client ID, legacy saved favorites.
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

Schema differences, confirmed with live read-only requests:

- **Tenrai** is Jikan-v4 compatible and uses **snake_case**: `data.mal_id`, `title_english`, `titles[]`,
  `images.jpg.large_image_url`, `pagination.has_next_page`, reviews with `mal_id`/`review`/`is_spoiler`/`tags`/`user`,
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
| `{anime,manga}/{id}/stacks?page=` | interest stacks that contain the title (25/page) |
| `stacks/{id}` | stack description, author, badges and entries |
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
- `includesEnglishTitleField` marks rows as “sparse”; sparse rows without an English title set `needsTitleLookup`,
  which `PreferredTitle` resolves through `API.resolveTitle` (6 concurrent lookups, de-duplicated per title) unless
  the page already named the row. A person page batches its credits through `API.titleNames` — one `ids` request
  per 50 titles — and passes `knownName`/`nameSettled`, so a mangaka with 26 credits costs one request instead of
  26; a name the batch did not return means there is no English title, not another lookup. Resolved names are
  persisted only in the friends-feed cache (`feedEnglishNames`).
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

1. **Client ID**: UserDefaults `aniswift.mal.nativeClientID` → Info.plist `AniswiftMALClientID` (CI can inject it)
   → prompt in `SignInButton` on a first sign-in. Settings → Behavior also sets or clears it, validating the same
   `^[A-Za-z0-9]{32}$` shape and showing only the last four characters.
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

## 8. Caching and concurrency

| Layer | Behaviour |
| --- | --- |
| Catalog memory cache | 5-minute TTL keyed by resolved URL, 1 minute for `users/*` lists, friends and activity so user data refreshes on open; capped at 160 entries with oldest-first eviction; `refresh: true` bypasses reads but still writes. A title page also seeds `record` from `cachedDetail` so a revisit paints its summary and sections before the network answers. `hasCachedCatalog` lets Settings report catalog-only caches; `clearCatalogCache()` drops the dictionary and the saved detail files. |
| Saved title pages | `Caches/AniswiftDetailCache/<kind>-<id>-full.json`: the raw `anime|manga/{id}/full` body written after a successful catalog read (< 2 MB). Used only when the live request fails and nothing is in memory: the page paints the saved payload under a “Showing saved data” note with Retry, instead of an error or an empty screen. |
| In-flight de-duplication | one shared `Task` per catalog URL |
| Title lookups | one `Task` per `Title.id`; a 6-slot `CheckedContinuation` gate limits concurrent Tenrai detail fetches |
| List snapshot | `Aniswift-lists-v1.json`: account + `[Kind: SavedList(items, page, more, needsReconciliation)]` |
| Friends feed | `Aniswift-friends-feed-v1.json`: account ID, friends, activity, checked count, history cursors, page, English names |
| Public profiles | `Aniswift-profiles-v1.json`: stats/favorites per user with **15-minute** freshness |
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
  out up to 5 requests concurrently (`/full`, reviews and stacks always; characters and recommendations only when
  those sections are enabled); friends'-activity scanning looks up 6 friends per batch concurrently.
- List sync re-fetches the whole loaded page range as a unit. A `listRevisions[kind]` counter aborts a sync if an
  edit lands mid-flight and sets `needsReconciliation` so the next page load re-syncs. Edits are applied
  optimistically.
- Every account-scoped mutation checks `accountGeneration`, so a sign-out cannot write into a new session.
- A friend-feed refresh resets `friendFeedPage` to 0 before incrementing, so the persisted page counter restarts
  with the refreshed snapshot instead of drifting upward across pull-to-refreshes.

## 9. Feature map

| Tab / screen | Reads | Writes |
| --- | --- | --- |
| Anime, Manga (`ListsScreen`) | cached list grouped by status (on-hold/dropped collapsed), search across loaded entries, sort by recent/title/rating, pagination; the empty state appears only for a loaded, empty snapshot | swipe +1 episode/chapter, swipe remove, full editor |
| Discover | 10 shelves, per-kind search, genre/theme/studio/producer facets, catalog browser with season/year pickers | — |
| Feed | friends list, per-friend `userupdates` (anime + manga), older pages via persisted cursors, English-name backfill; keeps the saved feed with a “Showing saved data” note and retry when Jikan Edge fails or reports stale data | — |
| Profile | account, public statistics, favorites, custom lists, legacy favorites, About/version; saved snapshot stays visible with a note and retry when the public data cannot be refreshed | sign in/out, client-ID change |
| Title | detail, relations, cast, recommendations, trailer, themes, interest stacks, reviews, friends' activity; tapping the header poster opens it full screen, and a manga's authors open their own page; header, content and information groups follow the Details Page settings, and the hidden character and recommendation sections are never requested | add/edit/remove entry, mark completed, quick status/progress/score, full editor (rewatch count, dates, notes ≤ 4000 bytes, custom lists, hide), share, open on MAL |
| Character | biography, member favorites, Japanese-preferred voice actors (each opening their own page), anime/manga appearances | — |
| Voice actor or mangaka (`PersonScreen`) | `people/{id}/full`: portrait, alternate names, birthday, member favorites, biography, voiced roles (main parts first, 12 then all) and anime/manga staff credits (8 then all); a role opens its character, a credit opens its title through `PreferredTitle`, which takes the credit's English name from one batched `titleNames` request per kind. Opened from a character's voice actors and from the authors a manga's header lists | — |
| Friend profile | stats header, list buttons only for non-empty lists, recent updates, favorites, pull-to-refresh | — |
| Settings | `@AppStorage` preferences, cache sizes, version and service credits | accent, language, link handling, score prompt, launch screen, tab bar, 31 detail toggles, cache clearing |

Design system: black canvas, forced dark scheme, shared `LedgerLayout` metrics, one `LedgerShelf` carousel for
every rail, one `LedgerViewAll` link and one `ledgerSearch` bar (`LedgerSearch`: a Liquid Glass capsule field with
round glass buttons, on screen only while its button is open) across screens, a configurable
tint (White default; eight other accent choices), Liquid Glass on iOS 26 with material/bordered fallbacks,
`ViewThatFits` and adaptive grids for accessibility sizes, empty states as page blocks or `ContentUnavailableView`,
`.sensoryFeedback` on controls plus success/error haptics, `SkeletonBlock` first-load placeholders on title pages,
lists, Discover and the feed, `plainMessage` for every failure sentence, VoiceOver labels and hints throughout,
and an in-app `SFSafariViewController` whose controls use the selected accent.

## 10. Settings and personalization

All preferences are stored in `UserDefaults.standard` under `aniswift.settings.*` and read with `@AppStorage`,
so a change updates open screens without a restart. The 31 Details Page toggles are the exception: a title page
reads them once into a `DetailPreferences` value per kind and refreshes it on `UserDefaults` changes, instead of
asking `UserDefaults` thirty-one times on every body pass. They are **device-wide**: switching MyAnimeList accounts or
signing out does not reset them, and they never sync.

| Preference | Key | Default | Effect |
| --- | --- | --- | --- |
| Accent Color | `accent` | `White` | `.tint` at the app root, controls, links, highlights and the in-app browser's controls. Choices: White, Blue, Red, Green, Brown, Cyan, Gray, Purple, Mint. The selection ring/checkmark animation is skipped under Reduce Motion. |
| Preferred Title Language | `titleLanguage` | `English` | Display-only name choice through `Title.displayName(for:)`; English falls back to Romaji and vice versa. Used by title pages, `PreferredTitle` tiles/rows, list sorting, stack entries, review headers/reader and editor prompts. List search matches either name. |
| Open Links In-App | `openLinksInApp` | `true` | `OpenURLAction` presents http(s) links in `SFSafariViewController`; if no foreground scene can present it, the action returns `.systemAction` so the link still opens. |
| Ask for Score After Watching an Anime | `askForScore` | `true` | In `ListEditor`, a transition to `completed` with rating 0 opens the score prompt; the editor skips entries already completed, and the prompt never opens from the score sheet itself. The title's Mark completed action asks whenever the update is completed and the entry still has no score. Anime only. |
| Enable Preferred Launch Screen | `preferredLaunch` | `false` | `AniswiftApp.init()` chooses `launchTab` instead of `lastTab` for the initial tab. |
| Preferred Screen | `launchTab` | `anime` | Anime, Manga, Discover, Feed or Profile. |
| Last Used Tab | `lastTab` | `anime` | Written whenever the selected tab changes; used when preferred launch is off. |
| Tab Bar Behavior | `tabBarBehavior` | `never` | iOS 26 only: `never` (always visible) or `onScrollDown` (`.tabBarMinimizeBehavior`). |

Details Page toggles use `aniswift.settings.details.<anime|manga>.<section>` and all default to `true`. There
are 17 anime keys and 14 manga keys (31 total):

| Group | Section keys | UI |
| --- | --- | --- |
| Header | `header.poster`, `header.score`, `header.rank`, `header.popularity`, `header.creators` | Poster, average score, MAL rank, popularity, studios (anime) / authors (manga) |
| Content | `characters`, `trailer`, `related`, `source`, `openings`, `endings`, `recommendations` | Character list, trailer, related titles, source, openings, endings, recommendations; trailer/openings/endings are anime-only and the manga screen omits them |
| Information | `info.series`, `info.alternatives`, `info.genres`, `info.themes`, `info.creators` | Series information, alternative titles, genres, themes, studios and producers (anime) / serialization (manga) |

`source` is rendered inside the Series Information block, so hiding Series Information also hides the source line.
The following stay visible regardless of settings: summary, background, interest stacks, friends' list activity
and reviews. Hiding groups changes rendering only; the title page still requests
its usual five catalog payloads.

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
5. **Pagination is inferred** for public data (`hasNextPage` → `total` → `rows.count == limit`); MAL lists assume
   100/page; `friendEntry` scans up to 10 pages of 300.
6. **English titles for user lists.** Jikan Edge list rows carry no English title. The friends feed resolves each
   page through Tenrai's `{kind}?ids=` filter (one 50-title request instead of a detail request per row) before it
   publishes the rows, and keeps the names in the feed cache. Other list rows still fall back to a per-row detail
   fetch. The preferred-language setting affects display only, not what is fetched or stored.
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
15. **Details toggles cover two of six requests.** Characters and recommendations are no longer requested when
    their section is hidden, but the `/full` payload, reviews and stacks always run, and header
    toggles still fetch the payload behind them.
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
21. **Search is the app's own bar, so there is no system scope bar.** `ledgerSearch` draws the field itself and
    shows it only while its round button is open — `.searchable` could not promise that, because a placement
    decides whether its field shows on its own. While the bar is open it hides the navigation bar, so the field
    sits at the very top and its own round X stands in for the back button; closing it restores both. Discover's
    anime/manga switch therefore sits under the field as a segmented picker rather than in a scope bar.

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
