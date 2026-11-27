# Aniswift

## Users

One person tracking what he watches and reads, on his own iPhone and iPad, in short sessions: check what aired, move
an episode, look up a title. Who they are in full is in `PRODUCT.md`.

## Product

A native SwiftUI client for iOS 17 and later that reads the catalog and writes to MyAnimeList with no backend of its
own. The capability and constraint record is in `PRODUCT.md`; the visual world is in `DESIGN.md`.

## Constraints

No backend, database or account of its own. MyAnimeList is the account and the only write target, and the AniList copy
is one-way and permanent. The catalog is Tenrai first and Jikan Edge second. Client IDs are build-time only. The
appearance is dark only. `project.pbxproj` is never edited by hand, so a new Swift type goes into an existing file.
The reasons for each are in `PRODUCT.md`.

## Ethical stance

- No account of its own: nothing is kept beyond the tokens and snapshots a provider requires.
- No analytics, telemetry or crash reporting beyond what iOS itself does.
- No notifications, streaks, badges or re-engagement prompts. The reader opens the app when he has a question.
- Every write to MyAnimeList is the change he made or the Undo of one, and the copy into AniList is stated in Settings
  where the session lives.
- The catalog patterns this product is tempted by, and refuses: infinite scroll as a session extender, pull-to-refresh
  as a lever that might reveal something new, and loss framing that punishes a missed day. Each is refused because
  the app's job is to answer a question, not to extend a visit.

## Success

The reader finds the answer and closes the app. A list that matches MyAnimeList, a title page that opens with its
answers, a countdown that stays right through a season break, and no visit longer than the question that opened it.

## Open questions

- Should the AniList copy be visible as history, or is one line in Settings the right amount to say?
