# Aniswift for iOS

Aniswift is a native SwiftUI anime and manga tracker for iPhone and iPad running iOS 17 or newer. It uses
MyAnimeList for accounts and personal lists, Tenrai for catalog data, and Jikan Edge for catalog fallback and
public friend activity.

Cover art and avatars use [Kingfisher](https://github.com/onevcat/Kingfisher) for image loading and memory and
disk caching, decoded at the size they are drawn. Xcode resolves the package on the first build.

## Run on a Mac

1. Open `Aniswift.xcodeproj` in Xcode 26 with the iOS 26 SDK installed.
2. Select the **Aniswift** scheme and an iPhone or iPad simulator. Press Run.
3. For a physical device, select your team under **Signing & Capabilities**, choose a bundle ID available to
   that team if needed, and run on the device.

Command line simulator build:

```sh
xcodebuild -project ios/Aniswift.xcodeproj -scheme Aniswift \
  -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build
```

## Using Aniswift

| Tab | What you can do |
| --- | --- |
| Anime and Manga | Expand status groups, sort by title, recent update or your rating, and search loaded entries, fetch more pages, and use swipe actions to update progress or remove a title. |
| Discover | Search anime and manga using the system search field, browse releases and rankings, and open title details. |
| Feed | Browse public friend updates, gathered from a dozen friends at a time and from their list pages while that is thin. Tap a name or avatar to open a native profile. Tap a title or poster to see its details. |
| Profile | View account statistics, friends and public favorites, open custom lists, share your MyAnimeList profile, choose what appears under **Settings → Profile**, and open Settings from the toolbar gear. |

Friend profiles show public stats, recent list updates newest first, and favorite anime and manga. Tap a favorite
or a recent update to open its title. Back returns to the friend's profile, then to the Feed. Pull down to
refresh the profile. Every list, a friend's list, catalog results, the catalog browser, reviews and interest
stacks refresh the same way. Lists, Discover and the Feed draw skeleton placeholders while their first page of
content loads, then replace them with the real rows and shelves.

Title pages show English titles when **Settings → Behavior → Preferred Title Language** is English and a
translation exists, or the Romaji title when Romaji is selected; each choice falls back to the other name when
it is missing. The same rule applies to posters and
rows, list sorting, interest-stack entries, review headers, and editor prompts. Genres, themes, producers and
serializations wrap onto additional lines. Relations, Characters and Recommended shelves share portrait sizing,
compact captions and a **View All** grid. Character profiles show biographies, voice actors and linked
appearances. A voice actor opens their own page: portrait, alternate names, birthday, member favorites,
biography, their voiced roles with main parts first, and their anime and manga staff credits — a role leads
back to its character, a credit to its title. A manga's header lists its authors the way a title lists its
studios, and tapping one opens that page. Reviews and friends' title activity appear when entries exist.
Open **View All** in Reviews to browse and read reviews inside the app, including a spoiler reveal control in
the reader. Interest stacks open from a title and list their entries with positions, scores and notes; in a
stack flagged **Spoilers**, each author note stays behind **Reveal note**. Many stacks chain themselves together
with lines like `Part 2: https://myanimelist.net/stacks/6746`; those links open the stack they name inside the
app rather than in a browser, so the parts can be read one after another. A title page you opened before can
be drawn from its saved copy without a connection, marked **Showing saved data** with a Retry. Tapping the
header poster shows it full screen, where a pinch looks closer and a tap closes it. A synopsis with more than
one paragraph starts with its first paragraph and a **Show more** control. Anime details can also include
trailers and theme songs.

Use **Status**, **Progress** or **My Score** for a quick edit. The pencil opens the full editor for repeat
counts, start and finish dates, and notes. These fields sync to MyAnimeList. Custom lists and visibility
preferences stay on this device for the signed-in account. Hidden status entries remain searchable. Status
controls use interactive Liquid Glass on iOS 26 and translucent material on earlier versions.

## Settings

Open **Profile → gear → Settings**. Settings also holds About Aniswift and Sign Out; the share button at the top
left of Profile shares your MyAnimeList profile. Settings apply to the whole app and are stored on this device;
they are not per account and are never synced to MyAnimeList.

### Accent Color

Nine swatches — White (default), Blue, Red, Green, Brown, Cyan, Gray, Purple and Mint — set the app-wide tint
used for controls, links, highlights and the in-app browser's controls. The selected swatch animates a ring and
checkmark, or updates without animation when Reduce Motion is on.

### Behavior

| Setting | Default | Effect |
| --- | --- | --- |
| Preferred Title Language | English | Shows English titles when a translation exists, otherwise the original; Romaji shows the original title with the English name as fallback. Applies to title pages, lists, shelves, sorting, stacks, reviews and editor prompts. |
| Open Links In-App | On | Opens http(s) links from titles, profiles, stacks and About in a Safari sheet inside Aniswift. When off, links open in the default browser. If no foreground window can present the sheet, the link opens outside the app instead of being dropped. |
| Ask for Score After Watching an Anime | On | After an anime is marked completed with no score — from the title's completion action, the quick status editor or the full editor — presents a score sheet. It never appears for manga or from the score editor itself; the editor path also skips an entry that was already completed. |
| Enable Preferred Launch Screen | Off | When on, the app opens the selected screen (Anime, Manga, Discover, Feed or Profile) on every cold launch. When off, it restores the last tab you used. |
| Preferred Screen | Anime | The tab used when preferred launch is enabled. |
| MyAnimeList Client ID | The ID the build ships with | Sets the 32-character iOS app ID used to sign in. The row shows only its last four characters; an empty field goes back to the bundled ID. |
| Tab Bar Behavior (iOS 26) | Always Visible | Keeps the tab bar visible or lets it minimize while scrolling down. Earlier iOS versions always show the tab bar. |
| Clear Cache | — | Clears Kingfisher's memory and disk image cache, the shared URL cache, the in-memory catalog response cache and the saved title pages. Sign-in, lists, feed/profile snapshots, custom lists and settings are kept. The row reports the measured image and URL cache size, or notes when only catalog responses are cached. |

Preferences are read live: changing the accent, language, a detail toggle or a profile toggle updates open
screens immediately.

### Details Page

Details Page settings control what a title page draws. Every toggle defaults to on, for both anime and manga,
and the groups are configured separately.

**Sections** (Anime and Manga)

- Show Sections Below Summary — one switch that hides everything under a title's summary: its information,
  background, related titles, characters, recommendations, stacks, trailer, theme songs, friends' activity and
  reviews

**Header** (Anime and Manga)

- Show Poster
- Show Average Score
- Show MAL Rank
- Show Popularity
- Show Studios (anime) or Show Authors (manga)

**Content** (Anime)

- Show Character List
- Show Trailer
- Show Related Anime
- Show Source
- Show Openings
- Show Endings
- Show Recommendations

**Content** (Manga)

- Show Character List
- Show Related Manga
- Show Source
- Show Recommendations

**Information** (Anime and Manga)

- Series Information — includes the source line, which also follows Show Source
- Alternative Titles
- Genres
- Themes
- Studios and Producers (anime) or Serialization (manga)

The summary is not configurable and always appears when data exists. With **Show Sections Below Summary** off, a
title page draws only its header and summary, and the section requests are skipped. Hiding Characters or
Recommendations on their own also skips its request, so the title page asks for less. The remaining toggles only
change what is drawn.

### Profile

Profile settings, under **Settings → Profile**, choose what the Profile tab draws. Every switch defaults to on.

**Appearance**

- Friends — the shelf of MyAnimeList friends, each opening their profile; hiding it skips the friends request
- Days Watching — the days-watched metric in the header
- Anime Statistics and Manga Statistics — the status counts, mean score and totals for each kind
- Favorite Anime and Favorite Manga — the favorite shelves
- Favorite Characters and Favorite People — the favorite character and voice actor shelves

### AniList

**Settings → AniList** signs this device in to AniList and shows its lists, read-only, beside MyAnimeList.
Nothing is written back to AniList.

1. Create an app at [anilist.co/settings/developer](https://anilist.co/settings/developer) with the redirect URL
   `org.aniswift.ios://oauth`, and copy its client ID. The build already ships one (ending in **8162**), so you
   can skip this and connect straight away; your own ID replaces it.
2. Tap **AniList Client ID** only to use your own app: paste the number and save. Clearing the field goes back to
   the ID the build ships with.
3. Tap **Connect AniList** and finish the sign-in sheet. The section then lists the account's anime and manga
   entries grouped by status, with posters, progress and scores, and **Sign Out of AniList** ends the session
   without touching the MyAnimeList one.

The lists are read through AniList's GraphQL API when the screen opens and on pull-to-refresh; the session is
kept in the Keychain and lasts a year.

### About

Settings also links to **About Aniswift**: version and build, the three data providers, open-source library
credits, and source and support links. When signed in,
**Sign Out** ends this device's MyAnimeList session and returns to the signed-out profile.

## Data and caching

| Source | Used for |
| --- | --- |
| MyAnimeList | Direct OAuth, private lists and list edits |
| Tenrai | Preferred catalog source for search, rankings, details, reviews and stacks |
| Jikan Edge | Catalog fallback and public friends, favorites, statistics and activity |
| Device storage | Keychain tokens, list/feed/profile snapshots, cached artwork and responses, preferences and custom lists |

Aniswift can restore already downloaded list pages while it syncs with MyAnimeList. Kingfisher caches posters
and avatars. Signing out clears the active session and its downloaded list snapshot; it does not reset settings,
which stay on the device. Clearing the cache from Settings removes images, URL responses and in-memory catalog
data without touching sign-in, lists, saved feed/profile snapshots or custom lists. Public profile sections
depend on what the provider can retrieve.

Snapshots are encoded on the screen's actor and written through one serial background queue, so a list edit or a
feed page never waits on the disk. `Aniswift/PrivacyInfo.xcprivacy` carries the app's privacy manifest: no
tracking, no data collected by the developer, and required-reason access for `UserDefaults` and file timestamps.

## Direct MyAnimeList connection

The iOS app calls MyAnimeList directly for authentication, personal lists and list edits. Tenrai and Jikan Edge
provide catalog data and public activity. List snapshots, artwork caches, saved title pages and custom lists are
stored on the device.

1. At [MyAnimeList API settings](https://myanimelist.net/apiconfig), create an application with App Type `iOS`.
2. Register the exact redirect URL `org.aniswift.ios://oauth`.
3. In Aniswift, tap **Sign in with MyAnimeList**, enter that iOS app's Client ID, and complete the browser
   sign-in. To change it later, open **Settings → Behavior → MyAnimeList Client ID**.

The app exchanges the authorization code and refreshes tokens directly with MyAnimeList. Tokens are stored in
the device-only Keychain. Sign-in, live list sync, and catalog updates require an internet connection.

An unsigned simulator build can run on a Mac simulator. Installing on an iPhone or distributing through
TestFlight requires signing with an Apple developer team.

## GitHub Actions IPA

To preconfigure sign-in in builds from `main`, add a repository Actions secret named `MAL_IOS_CLIENT_ID` with
your native MyAnimeList iOS Client ID. The workflow embeds it in the IPA so users can sign in without entering
an ID. If the secret is absent, the app prompts for an ID on first sign-in.

GitHub keeps the secret out of the repository and build logs. The Client ID is readable from a distributed IPA.
If your registration requires the Client ID to remain undisclosed, leave the secret unset for public releases
and enter it on the device. Use the iOS Client ID only.

The **Build Aniswift IPA** workflow runs on pushes to `main`, on tags matching `ios-v*`, on pull requests
touching `ios/**` or the workflow, and manually. Each run builds one tree — the tip of the push, the tagged
commit or the pull request — and uploads `Aniswift-Unsigned.ipa` as a workflow artifact. The unsigned file is a
device build and requires signing before iOS can install it.

A release is a tag. Push one (`git tag ios-v1.0.0 && git push origin ios-v1.0.0`) and the run publishes a
[GitHub release](https://github.com/jacobxhoang/aniledger/releases) of that name with the IPA attached; a branch
push publishes nothing. A newer push of the same branch cancels the run it supersedes.

### Nightly builds

Every push to `main` also republishes one rolling prerelease, the way SideStore runs its nightly channel. The
`nightly` tag moves to the pushed commit and the asset keeps its name, so this link never changes:

```text
https://github.com/jacobxhoang/aniledger/releases/download/nightly/Aniswift-Nightly-Unsigned.ipa
```

That file is the tip of `main`, rebuilt on every push with the commit count as its build number — About
Aniswift shows it, so two nightlies can be told apart — and its release notes list the commits since the previous
one. It is unsigned like every artifact: sign it with your own profile, or import it into a sideloading tool, before
installing it on a device. `releases/latest` skips prereleases, so the stable download stays the newest `ios-v*`
tag. While `TESTS_GATE` is off a red suite still publishes a nightly; setting the gate stops that.

For an installable Ad Hoc IPA, use an Apple Distribution certificate with its private key in a password-protected
`.p12`, and an Ad Hoc provisioning profile for an explicit App ID that includes the devices you want to install
on. Add these repository Actions secrets:

| Secret | Value |
| --- | --- |
| `IOS_CERTIFICATE_BASE64` | Base64-encoded distribution `.p12` |
| `IOS_CERTIFICATE_PASSWORD` | Password used to export the `.p12` |
| `IOS_PROFILE_BASE64` | Base64-encoded Ad Hoc `.mobileprovision` |

In **Actions → Build Aniswift IPA → Run workflow**, enable **signed**. Download the `Aniswift-Signed` artifact.
The workflow uses the App ID and team from the provisioning profile and exports for its registered devices.

## Development tools

- **Formatting** uses `swift-format` from the Xcode 26 toolchain with the repository's `.swift-format`
  (120-column limit, 4-space indentation, existing line breaks respected):
  ```sh
  xcrun swift-format lint --strict --configuration .swift-format $(git diff --name-only origin/main -- 'ios/*.swift')
  ```
  The workflow's `format` job lints only the Swift files a change touches, so existing files are not
  reformatted in bulk, and reports a finding as a warning with the formatted copy attached rather than
  failing the run.
- **Tests** use Swift Testing in the `AniswiftTests` target and cover the shared decoder, title parsing, the
  activity-date heuristics, the store's list sync and failure reporting, the friend-feed cursor bookkeeping and
  the OAuth callback validation. The `test` job runs them on the newest available iPhone simulator. The IPA build
  depends on that job, but while the suite is still unproven the dependency is advisory: a red run is visible in
  CI without stopping releases. Set the repository variable `TESTS_GATE` to `on`
  (Settings → Secrets and variables → Actions → Variables) once the suite is green, and a failing run will then
  block the IPA and the release. Run them locally with:
  ```sh
  xcodebuild test -project ios/Aniswift.xcodeproj -scheme Aniswift \
    -destination 'platform=iOS Simulator,name=iPhone 16'
  ```
## Verification checklist

- Build in Xcode and exercise search in Anime, Manga and Discover, and switch Discover's anime/manga picker.
- Open a title with several genres or producers. Check wrapping at standard and large text sizes.
- Swipe the Relations, Characters and Recommended shelves. Open **View All** and select an item.
- Open **Settings** from the Profile gear. Change the accent and confirm controls, links and the Safari sheet
  tint follow it.
- Switch **Preferred Title Language** to Romaji and check a title header, list rows, title sorting, an interest
  stack entry, a review header and the full editor's notes prompt. Switch back to English.
- Turn on **Preferred Launch Screen**, choose a tab, terminate and relaunch the app. Turn it off and confirm the
  last-used tab is restored instead.
- Mark an anime completed without a score with **Ask for Score** on and confirm the score sheet; repeat with the
  setting off.
- Toggle header and information groups for one kind and confirm only that kind's title pages change. Confirm
  Source disappears when Series Information is hidden.
- Open a link with **Open Links In-App** on and off; confirm the sheet and the system browser respectively.
- With posters cached, open **Clear Cache**, confirm the size, clear, and reopen a title to confirm it reloads.
  Confirm sign-in, lists and settings survive.
- From the Feed, open a friend's profile and select a favorite. Confirm the title takes over the page and Back
  returns to the same profile. Repeat for a recent list update and for a title opened directly from the Feed.
- Open a character with a Japanese voice actor and tap one. Confirm the voice actor page shows their roles and
  staff credits, that a role opens its character, and that Back returns to the same voice actor.
- Open a manga and tap an author in its header. Confirm their page lists the manga they worked on, that a
  credit opens that title, and that Back returns to the manga.
- Open a stack flagged **Spoilers**. Confirm each note shows **Reveal note** until tapped, and that a stack
  without the flag still shows its notes immediately. On a stack whose description links to other stacks,
  confirm a link opens that stack in the app and Back returns to the first one.
- Turn off **Show Character List** and **Show Recommendations**, open a fresh title page and confirm both
  sections are absent and the page loads without waiting for them. Turn them back on.
- Open a title, enable Airplane Mode, and open the same title again. Confirm it draws with a **Showing saved
  data** note and a Retry, instead of an error.
- Open a title from an interest stack, the stacks list, a review author, the catalog browser, a Discover shelf,
  a custom list and a friend's media list. Each detail page must slide in over the current screen rather than
  appearing behind it, and Back must return to the same list.
- Use a signed device build and a registered iOS Client ID to verify account sync and Liquid Glass on iPhone.
