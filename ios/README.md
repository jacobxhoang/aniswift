# AniLedger for iOS

AniLedger is a native SwiftUI companion to the AniLedger website for iPhone and iPad running iOS 17 or newer. It uses MyAnimeList for accounts and personal lists, Tenrai for catalog data, and Jikan Edge for catalog fallback and public friend activity.

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

## Backend

The app connects to `https://ani-ledger.onrender.com`. The hosted service must have the existing MyAnimeList OAuth environment variables and the mobile authentication routes in this revision. The existing HTTPS callback registered with MAL is used for both the website and the native app. No MyAnimeList client secret goes in the Xcode project.

The system authentication browser returns a short-lived encrypted handoff to the app. The app exchanges it using a device-generated verifier and stores the resulting session in Keychain. Signing out removes the local session. List edits require an internet connection.

An unsigned simulator build can run on a Mac simulator. Installing on an iPhone or distributing through TestFlight requires signing with an Apple developer team.

## GitHub Actions IPA

The **Build AniLedger IPA** workflow archives the app for iPhone and iPad and uploads `AniLedger-Unsigned.ipa` on iOS source changes. The unsigned file is a device build and requires signing before iOS can install it.

For an installable Ad Hoc IPA, use an Apple Distribution certificate with its private key in a password-protected `.p12`, and an Ad Hoc provisioning profile for an explicit App ID that includes the devices you want to install on. Add these repository Actions secrets:

| Secret | Value |
| --- | --- |
| `IOS_CERTIFICATE_BASE64` | Base64-encoded distribution `.p12` |
| `IOS_CERTIFICATE_PASSWORD` | Password used to export the `.p12` |
| `IOS_PROFILE_BASE64` | Base64-encoded Ad Hoc `.mobileprovision` |

In **Actions → Build AniLedger IPA → Run workflow**, enable **signed**. Download the `AniLedger-Signed` artifact. The workflow uses the App ID and team from the provisioning profile and exports for its registered devices.
