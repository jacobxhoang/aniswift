# AniLedger

AniLedger is a responsive anime and manga tracker with a MyAnimeList-inspired dashboard. It uses Tenrai for catalog data, Jikan Edge when Tenrai is unavailable, and the official MyAnimeList API for account sign-in and personal list changes.

## Choose a client

| Client | Getting started | Account connection |
| --- | --- | --- |
| Web | [Live dashboard](https://ani-ledger.onrender.com/) or the local setup below | Hosted Web OAuth through AniLedger |
| iOS | [iOS setup and release guide](ios/README.md) | Direct MyAnimeList OAuth with a separate iOS Client ID |

## Web features

- Shows recent anime and manga list updates at the top of the dashboard, followed by this season's anime, catalog picks, statistics, and friends' public list activity.
- Browses anime and manga, searches the catalog, and opens title details without requiring an account.
- Signs in through MyAnimeList OAuth. AniLedger never asks for or stores a MyAnimeList password.
- Reads the signed-in user's anime and manga lists from MyAnimeList, including mature entries. Add, edit, and remove actions are written to the user's MyAnimeList list.
- Prefers English titles and uses romaji when an English title is unavailable. MyAnimeList list entries use their English alternative title when provided.
- Checks the existing session before showing account-dependent dashboard content. During that check the app shows a loading status; it doesn't briefly render the signed-out sign-in prompt. If the check fails, the user can retry.

The **Friends feed** shows public updates from followed users. Friends activity comes from Jikan Edge, which exposes the public user-update feed. Feed dates are interpreted using the feed's fetch time, including relative dates such as “Yesterday” and entries without a year.

## Data sources

| Data | Source | Behavior |
| --- | --- | --- |
| Anime and manga catalog, season, rankings, and title metadata | [Tenrai](https://tenrai.org/) | Tried first for catalog requests |
| Catalog fallback and public friends activity | [Jikan Edge](https://jikan.lucashdo.com/docs) | Used if a Tenrai catalog request fails; used directly for public user updates |
| Account profile, personal lists, and list edits | [MyAnimeList API](https://myanimelist.net/apiconfig) | Requires the app owner's OAuth credentials and the user's authorization |

Catalog requests are cached in memory while the app is running. A successful fallback is retried against Tenrai after one minute so the preferred provider can recover without a restart. MyAnimeList list requests include `nsfw=true` so mature list entries are not filtered out.

## Requirements

- Node.js 22 or newer.
- No third-party npm packages are required.
- OAuth credentials are required only for MyAnimeList sign-in and personal list access. Catalog browsing works without them.

## Run locally

```sh
npm run dev
```

Open <http://localhost:4173>. The development command builds the app and starts the local server. The server listens on all interfaces (set `PORT` to change the port) and answers whatever hostname it is reached at, so tunnels, preview URLs and LAN addresses work; list writes keep their same-origin check. To check JavaScript syntax and build the deployable bundle:

```sh
npm run check
npm run build
```

The build produces `dist/server/index.js`, a self-contained Worker module. `npm start` runs that built module behind the included Node HTTP adapter; build it first with `npm run build`.

## Configure MyAnimeList OAuth

1. Register a **Web** application in [MyAnimeList API settings](https://myanimelist.net/apiconfig).
2. Set its redirect URL to the exact callback for the environment you are configuring:
   - Local: `http://localhost:4173/auth/mal/callback`
   - Production: `https://YOUR-SITE/auth/mal/callback`
3. Copy `.env.example` to `.env` for local development. Set `MAL_CLIENT_ID` and `MAL_CLIENT_SECRET` to the values MyAnimeList issued, and set `MAL_REDIRECT_URI` to the callback URL registered for that environment. `MAL_SESSION_SECRET` is optional; set it to a long random value if you want a session-encryption key separate from the client secret.
4. Restart the local server after changing `.env`. For deployment, configure these values as private runtime environment variables in the hosting service. Never commit `.env` or put OAuth secrets in browser JavaScript.

OAuth starts at `/auth/mal` and returns to `/auth/mal/callback`. The callback exchanges the authorization code with MyAnimeList and checks the account profile before creating a session. Session and refresh tokens are held in encrypted, `HttpOnly`, `SameSite=Lax` cookies. Cookies use `Secure` over HTTPS. Sessions expire after 30 days; an expired MyAnimeList access token is refreshed when possible. Signing out clears the local session cookies.

If OAuth isn't configured, catalog browsing remains available. The account prompt provides a setup message rather than starting an incomplete sign-in flow.

## API routes

The app serves its browser client, OAuth routes, and JSON API from one origin.

| Method and path | Purpose | Sign-in required |
| --- | --- | --- |
| `GET /auth/mal` | Start MyAnimeList OAuth | No |
| `GET /auth/mal/callback` | Complete OAuth and create a local session | OAuth callback |
| `GET /api/session` | Check OAuth configuration and current user | No |
| `POST /api/logout` | Clear the local session | No |
| `GET /api/lists/anime?page=1` | Read a page of the user's anime list | Yes |
| `GET /api/lists/manga?page=1` | Read a page of the user's manga list | Yes |
| `GET /api/suggestions/anime` | Read personalized anime suggestions | Yes |
| `GET /api/lists/{anime\|manga}/{id}` | Read an individual list entry | Yes |
| `PUT /api/lists/{anime\|manga}/{id}` | Update status, progress, score, and any supplied repeat count, dates, or notes | Yes |
| `DELETE /api/lists/{anime\|manga}/{id}` | Remove an entry from the list | Yes |

Web list writes go to MyAnimeList through the server. Browser writes must pass the same-origin check. Current iOS builds authenticate and write directly to MyAnimeList.

## Deploy on Render

This repository is configured for a Render Node web service:

- Build command: `npm run build`
- Start command: `npm start`
- Runtime: Node.js 22 or newer
- Health and public origin: Render provides `RENDER_EXTERNAL_URL`; the adapter uses it for HTTPS origin validation and OAuth cookies.
- Environment variables: set `MAL_CLIENT_ID`, `MAL_CLIENT_SECRET`, `MAL_REDIRECT_URI`, and optionally `MAL_SESSION_SECRET` in the service's private environment settings. The production redirect URI must match the callback registered in MyAnimeList exactly.

When using another production host, set `APP_ORIGIN` to the public HTTPS origin with no path, and configure that same origin's `/auth/mal/callback` as the OAuth redirect URI. The service listens on the host-provided `PORT`.


## Repository layout

| Path | Purpose |
| --- | --- |
| `web/` | Browser dashboard, search, title pages, and styles |
| `worker.js` | Web authentication, sessions, and MyAnimeList API routes |
| `scripts/build.mjs` | Packages the web assets and server |
| `scripts/preview.mjs` | Runs the web build on Node |
| `ios/AniLedger/` | Native SwiftUI app, API client, and local cache |
| `.github/workflows/ios.yml` | Builds iOS IPAs and publishes prereleases |

## Troubleshooting

- **Web sign-in fails.** Check your Web OAuth registration, environment variables, and exact callback. The iOS app uses a separate registration.
- **A friend’s activity is missing.** The feed depends on public updates that Jikan Edge can retrieve.
- **A title appears in romaji.** AniLedger prefers English when the data source supplies an English title.
- **An IPA will not install.** The published IPA requires signing. See the [iOS build instructions](ios/README.md#github-actions-ipa).
