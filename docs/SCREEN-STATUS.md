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

## Identity & Session Continuity

Not a screen — a cross-cutting behavior layered onto the existing Player
screens (01/02, 03, 05, 06, 07, 08, 09) without changing any of their visuals.
Tracked here rather than against one screen row because it touches five
routes at once: `/register`, `/register/alias`, `/register/whatsapp`,
`/pass`, and `/`.

**What it does:** one shared resolver (`resolvePlayerIdentity()`) now gates
all five routes, so a registered player can no longer reach onboarding
by URL, back button, or reload, and the landing page CTA reflects real
identity (`I'M IN` vs `OPEN YOUR PASS`) instead of guessing from
localStorage. A genuine identity-check failure (Supabase unreachable, not
"no registration") shows an explicit retry state rather than crashing or
silently guessing either direction — this replaced a real crash (500) that
existed before this slice, caught while building it.

**Status: `CONNECTED`, not `VERIFIED`.** The code is real, wired to the
real `get_player_state()`/`register_player()` architecture, and the guard
logic itself was proven — but proven locally and via a code-level harness,
not against the hosted product. See the delivery report for exactly what
was and wasn't exercised. Do not treat this as done until the hosted
acceptance flow (new visitor → register → returning player recognized →
refresh → duplicate-prevention) has actually been run.

## Player

| # | Screen | Visual | Data | Status |
|---|---|---|---|---|
| 01/02 | Landing (V2) | Reference supplied | Event | REVIEW |
| 03/04/05 | Registration (V2) — Name / Alias / WhatsApp | Reference supplied | Registration | REVIEW |
| 06 | You're In | Reference supplied | Registration | **Unreachable as of Registration V2** — see delivery report. The V2 WhatsApp step's own in-place "Registration Complete" transition now covers this moment; it no longer calls `markPassFresh()`, so this screen's trigger condition can never fire. Not deleted (Pass is a separate slice) — flagging for a decision alongside Pass's own V2 pass. |
| 07 | Event Pass | Reference supplied | Event | REVIEW |
| 08 | Check-in | Reference supplied | Check-in | REVIEW |
| 09 | Room | Reference supplied | Room | APPROVED |
| 10 | Live Game | Reference required | Round | REFERENCE |
| 11 | Between Games | Reference required | Score | REFERENCE |
| 12 | Results | Reference required | Leaderboard | REFERENCE |

Screens 01 (Arrival) and 02 (Landing) have merged into one V2 Landing slice:
the old splash → crossfade → landing sequence is gone, replaced by a single
state at `/`. Real UI/DOM content (event date/day/time/zone, the CTA's
label/destination) is separated from reusable brand art (wordmark, the "ALL
WORK. NO PLAY..." lettering, the pawn/die composition) — see the delivery
report for the asset-by-asset vector/raster decisions. **Not** self-approved
past `REVIEW`.

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
| RECESS wordmark (V2, vector trace) | `src/components/brand/v2/RecessWordmark.tsx` | 01/02, 03/04/05 |
| "ALL WORK. NO PLAY..." lettering + brush (V2, vector trace) | `public/brand/v2/all-work-no-play.svg` | 01/02 |
| Hero pawn + die composition (V2, raster — dimensional shading) | `public/brand/v2/hero-pawn-die.webp` | 01/02 |
| Name illustration — pawn + ticket (V2, raster) | `public/brand/v2/onboarding-name.webp` | 03 |
| Alias illustration — dimensional die + brush (V2, raster) | `public/brand/v2/onboarding-alias.webp` | 04 |
| WhatsApp illustration — ticket (V2, raster) | `public/brand/v2/onboarding-whatsapp.webp` | 05 |
| Pink exploding die | `public/brand/old/die-pink.webp` | 08 |

The V1 pawn/knight/rook assets (`pawn-pink.webp`, `knight-orange.webp`,
`rook-pink.webp`) and their sole component wrapper (`PawnMark.tsx`) are
retired with this slice — screens 03-05 now use the V2 illustrations above
instead. Found in passing: `die-pink.webp`'s path above changed from
`public/brand/die-pink.webp` because a prior asset reorganization moved it
to `public/brand/old/` without updating `CheckInScreen.tsx`'s reference,
leaving that image 404ing in production. Fixed as a one-line path
correction — not a Screen 08 redesign. See the delivery report.

A real `recess-wordmark` asset was supplied and used for V2 (traced to SVG,
see above) — screens 01/02 and, as of this slice, 03/04/05 all use it. The
pre-V2 approximation in `src/components/brand/RecessWordmark.tsx` remains
in use by screens 07-09 (all already `APPROVED`/`REVIEW` under its exact
output); migrating those is a call for whoever approves each of them next.

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
