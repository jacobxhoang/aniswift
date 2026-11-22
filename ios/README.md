# AniLedger for iOS

AniLedger is a native SwiftUI anime and manga tracker for iPhone and iPad running iOS 17 or newer. It uses MyAnimeList for accounts and personal lists, Tenrai for catalog data, and Jikan Edge for catalog fallback and public friend activity.

Cover art and avatars use [Kingfisher](https://github.com/onevcat/Kingfisher) for image loading and memory and disk caching. Xcode resolves the package on the first build.

## Run on a Mac

1. Open `AniLedger.xcodeproj` in Xcode 26 with the iOS 26 SDK installed.
2. Select the **AniLedger** scheme and an iPhone or iPad simulator. Press Run.
3. For a physical device, select your team under **Signing & Capabilities**, choose a bundle ID available to that team if needed, and run on the device.

Command line simulator build:

```sh
xcodebuild -project ios/AniLedger.xcodeproj -scheme AniLedger \
  -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build
```

## Using AniLedger

| Tab | What you can do |
| --- | --- |
| Anime and Manga | Expand status groups, sort and search loaded entries, fetch more pages, and use swipe actions to update progress or remove a title. |
| Discover | Search anime and manga using the system search field, browse releases and rankings, and open title details. |
| Feed | Browse public friend updates. Tap a name or avatar to open a native profile. Tap a title or poster to see its details. |
| Profile | View account statistics and public favorites, open custom lists, and manage sign-in. |

Friend profiles show public stats, recent list updates newest first, and favorite anime and manga. Tap a favorite or a recent update to open its title. Back returns to the friend's profile, then to the Feed. Pull down to refresh the profile.

Title pages prefer English titles with a romaji fallback. Genres, themes, producers and serializations wrap onto additional lines. Relations, Characters and Recommended shelves share portrait sizing, compact captions and a **View All** grid. Character profiles show biographies, voice actors and linked appearances. Reviews and friends’ title activity appear when entries exist. Open **View All** in Reviews to browse and read reviews inside the app. Anime details can also include trailers, themes, episodes and streaming links.

Use **Status**, **Progress** or **My Score** for a quick edit. The pencil opens the full editor for repeat counts, start and finish dates, and notes. These fields sync to MyAnimeList. Custom lists and visibility preferences stay on this device for the signed-in account. Hidden status entries remain searchable. Status controls use interactive Liquid Glass on iOS 26 and translucent material on earlier versions.

## Data and caching

| Source | Used for |
| --- | --- |
| MyAnimeList | Direct OAuth, private lists, list edits and personalized anime suggestions |
| Tenrai | Preferred catalog source for search, rankings and details |
| Jikan Edge | Catalog fallback and public friends, favorites, statistics and activity |
| Device storage | Keychain tokens, list snapshots, cached artwork and custom list organization |

AniLedger can restore already downloaded list pages while it syncs with MyAnimeList. Kingfisher caches posters and avatars. Signing out clears the active session and its downloaded list snapshot. Public profile sections depend on what the provider can retrieve.

## Direct MyAnimeList connection

The iOS app calls MyAnimeList directly for authentication, personal lists, list edits, and personalized anime suggestions. Tenrai and Jikan Edge provide catalog data and public activity. List snapshots, artwork caches, and custom lists are stored on the device.

1. At [MyAnimeList API settings](https://myanimelist.net/apiconfig), create an application with App Type `iOS`.
2. Register the exact redirect URL `org.aniledger.ios://oauth`.
3. In AniLedger, tap **Sign in with MyAnimeList**, enter that iOS app's Client ID, and complete the browser sign-in. To change it later, sign out and long-press the sign-in button.

The app exchanges the authorization code and refreshes tokens directly with MyAnimeList. Tokens are stored in the device-only Keychain. Sign-in, live list sync, and catalog updates require an internet connection.

An unsigned simulator build can run on a Mac simulator. Installing on an iPhone or distributing through TestFlight requires signing with an Apple developer team.

## GitHub Actions IPA

To preconfigure sign-in in builds from `main`, add a repository Actions secret named `MAL_IOS_CLIENT_ID` with your native MyAnimeList iOS Client ID. The workflow embeds it in the IPA so users can sign in without entering an ID. If the secret is absent, the app prompts for an ID on first sign-in.

GitHub keeps the secret out of the repository and build logs. The Client ID is readable from a distributed IPA. If your registration requires the Client ID to remain undisclosed, leave the secret unset for public releases and enter it on the device. Use the iOS Client ID only.

The **Build AniLedger IPA** workflow builds each new commit on the first-parent history of `main`. Each successful build publishes a [GitHub prerelease](https://github.com/jacobxhoang/ani-ledger/releases) tagged `ios-<full commit SHA>` with `AniLedger-Unsigned.ipa` attached. Pull requests can build artifacts without publishing releases. The unsigned file is a device build and requires signing before iOS can install it.

For an installable Ad Hoc IPA, use an Apple Distribution certificate with its private key in a password-protected `.p12`, and an Ad Hoc provisioning profile for an explicit App ID that includes the devices you want to install on. Add these repository Actions secrets:

| Secret | Value |
| --- | --- |
| `IOS_CERTIFICATE_BASE64` | Base64-encoded distribution `.p12` |
| `IOS_CERTIFICATE_PASSWORD` | Password used to export the `.p12` |
| `IOS_PROFILE_BASE64` | Base64-encoded Ad Hoc `.mobileprovision` |

In **Actions → Build AniLedger IPA → Run workflow**, enable **signed**. Download the `AniLedger-Signed` artifact. The workflow uses the App ID and team from the provisioning profile and exports for its registered devices.


## Verification checklist

- Build in Xcode and exercise search in Anime, Manga and Discover.
- Open a title with several genres or producers. Check wrapping at standard and large text sizes.
- Swipe the Relations, Characters and Recommended shelves. Open **View All** and select an item.
- From the Feed, open a friend’s profile and select a favorite. Confirm the title takes over the page and Back returns to the same profile. Repeat for a recent list update and for a title opened directly from the Feed.
- Use a signed device build and a registered iOS Client ID to verify account sync and Liquid Glass on iPhone.
