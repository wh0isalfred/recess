# RECESS Screen Status

Tracks visual implementation of every screen in the product, one screen at a
time. This is a progress tracker, not a spec — what a screen *is* lives in
`docs/PRODUCT.md`, what it looks like lives in the supplied reference.

## Workflow

| Status | Meaning |
|---|---|
| `REFERENCE` | Waiting on a supplied visual reference, or reference supplied but not started |
| `BUILDING` | Implementation in progress |
| `REVIEW` | Built, awaiting visual inspection |
| `APPROVED` | Visual approved; may still be on placeholder data |
| `CONNECTED` | Wired to real data and behaviour |
| `VERIFIED` | Checks run, acceptance criteria met, done |

One screen at a time. Two directly related states only when explicitly
requested. Nothing moves past `REVIEW` without approval.

## Player

| # | Screen | Visual | Data | Status |
|---|---|---|---|---|
| 01 | Arrival | Reference supplied | N/A | REVIEW |
| 02 | Landing | Reference supplied | Event | REVIEW |
| 03 | Registration — Name | Reference supplied | Registration | APPROVED |
| 04 | Registration — Alias | Reference supplied | Registration | APPROVED |
| 05 | Registration — WhatsApp | Reference supplied | Registration | REVIEW (local only — hosted registration path not yet exercised; see report) |
| 06 | You're In | Reference supplied | Registration | REVIEW (local only — hosted registration path not yet exercised; see report) |
| 07 | Event Pass | Reference supplied | Event | REVIEW |
| 08 | Check-in | Reference supplied | Check-in | REVIEW |
| 09 | Room | Reference supplied | Room | APPROVED |
| 10 | Live Game | Reference required | Round | REFERENCE |
| 11 | Between Games | Reference required | Score | REFERENCE |
| 12 | Results | Reference required | Leaderboard | REFERENCE |

## Coordinator

Not started. Screens to be listed when references are supplied.

| # | Screen | Visual | Data | Status |
|---|---|---|---|---|
| — | — | — | — | — |

## Admin

| # | Screen | Visual | Data | Status |
|---|---|---|---|---|
| A01 | Event Overview | Reference supplied | Live | APPROVED (now at /admin/events/[slug]/overview — see note below) |
| A02 | Rooms | Reference supplied | Live | APPROVED (now at /admin/events/[slug]/rooms — see note below) |
| A03 | Events list | No reference — operational tool | Live | REVIEW |
| A04 | New Event builder | No reference — operational tool | Live | REVIEW |

A01/A02 moved from fixed routes (`/admin/overview`, `/admin/rooms`) to
event-scoped routes (`/admin/events/[slug]/overview`, `/admin/events/[slug]/rooms`)
to support multiple events — required once event creation exists and a
separate test event is needed alongside the real one. Approval carries over;
the pixels are unchanged, only the URL and the data source (now
slug-parameterized instead of a fixed env var) moved.

## Final QA

Run once every player screen is `VERIFIED`.

| # | Pass | Status |
|---|---|---|
| — | — | — |

## Assets

| Asset | Path | Screens |
|---|---|---|
| Landing background artwork | `public/brand/landing-background.webp` | 02 |
| Arrival background artwork | `public/brand/arrival-background.webp` | 01 |
| Pink pawn | `public/brand/pawn-pink.webp` | 03 |
| Orange knight | `public/brand/knight-orange.webp` | 04 |
| Pink rook | `public/brand/rook-pink.webp` | 05 |
| Pink exploding die | `public/brand/die-pink.webp` | 08 |

Awaiting supply: `recess-wordmark.svg` and `brush-pink.svg`. Both are
approximated in `src/components/brand/RecessWordmark.tsx` until then — see
the note in that file.

Also awaiting supply — game artwork. Architecture is built (`games.artwork_url`,
same-origin-path-constrained, static files, no Storage bucket) and the UI
degrades gracefully to a branded fallback (`src/components/brand/GameArt.tsx`)
wherever it's used (Screen 07's GET READY, Screen 09's UP FIRST). The real
files are not yet supplied:

| Asset | Path | Screens |
|---|---|---|
| Among Us artwork | `public/games/among-us.webp` | 07, 09 |
| Skribbl artwork | `public/games/skribbl.webp` | 07, 09 |
| Trivia artwork | `public/games/trivia.webp` | 07, 09 |
