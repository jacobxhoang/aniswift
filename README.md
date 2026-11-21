# AniLedger

AniLedger is a dark, two-column anime and manga dashboard. [jikan-edge](https://jikan.lucashdo.com/docs) supplies the public catalog, seasonal releases, title details, and rankings. The official MyAnimeList API handles account authorization and list changes.

## Run locally

Use Node.js 22 or later. There are no package dependencies to install.

```sh
npm run dev
```

Open `http://localhost:4173`. You can browse and search the catalog without signing in. The signed-out dashboard shows sample activity. A small set of saved titles keeps the catalog browsable if jikan-edge is unavailable.

## Enable MyAnimeList sign-in

1. Register a **Web** application in [MyAnimeList API settings](https://myanimelist.net/apiconfig). Use the application's URL and register its exact callback URL. The local callback is `http://localhost:4173/auth/mal/callback`. Add `https://YOUR-SITE/auth/mal/callback` for your hosted instance.
2. Copy `.env.example` to `.env` and set `MAL_CLIENT_ID` and `MAL_CLIENT_SECRET` to the issued credentials. Set `MAL_REDIRECT_URI` to the registered callback URL. An optional random `MAL_SESSION_SECRET` allows independent session-key rotation.
3. Restart the local server or redeploy your hosted worker. In production, set these values in the host's runtime settings and store the secrets as encrypted variables.

Sign-in takes place on MyAnimeList. Once authorized, AniLedger loads the account's anime and manga lists. Saving or removing an entry updates MyAnimeList directly. Site sessions use encrypted HttpOnly cookies that expire after 30 days. Signing out clears the local session.

## Build

```sh
npm run check
npm run build
```

The build creates a self-contained Cloudflare Worker at `dist/server/index.js`. Serve the app and its API routes from the same origin. Set the OAuth callback to that origin's `/auth/mal/callback` path before deployment.
