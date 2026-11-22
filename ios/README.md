# AniLedger for iOS

AniLedger is a native SwiftUI companion to the AniLedger website for iPhone and iPad running iOS 17 or newer. It uses MyAnimeList for accounts and personal lists, Tenrai for catalog data, and Jikan Edge for catalog fallback and public friend activity.

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

## Features

- Home dashboard with recent list changes, seasonal anime, top airing and upcoming anime, and separate suggestion rows.
- MyAnimeList anime suggestions in the order returned for the authenticated user. Manga suggestions use catalog recommendations because MyAnimeList does not expose a comparable personalized manga endpoint.
- Anime and manga lists with status filters, paging, progress swipe actions, and editing for status, progress, and rating.
- Discover with native search and paged anime, manga, and seasonal browsing.
- Full title pages with related entries, cast, themes for anime, public friend activity, and spoiler-aware reviews with reviewer ratings.
- Public friends feed, profile access, and sign-out.

## Direct MyAnimeList connection

The iOS app calls MyAnimeList directly for authentication, personal lists, list edits, and personalized anime suggestions. Tenrai and Jikan Edge provide catalog data and public activity. List snapshots, artwork caches, and custom lists are stored on the device. The hosted AniLedger website uses its own web backend.

1. At [MyAnimeList API settings](https://myanimelist.net/apiconfig), create a separate application with App Type `iOS`.
2. Register the exact redirect URL `org.aniledger.ios://oauth`.
3. In AniLedger, tap **Sign in with MyAnimeList**, enter that iOS app's Client ID, and complete the browser sign-in. To change it later, sign out and long-press the sign-in button.

The app exchanges the authorization code and refreshes tokens directly with MyAnimeList. Tokens are stored in the device-only Keychain. Existing hosted iOS sessions require one new sign-in. Never enter the website's client secret in the app. Sign-in, live list sync, and catalog updates require an internet connection.

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
