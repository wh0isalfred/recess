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
| 05 | Registration — WhatsApp | Reference supplied | Registration | REVIEW |
| 06 | You're In | Reference supplied | Registration | REVIEW |
| 07 | Event Pass | Reference required | Player/Event | REFERENCE |
| 08 | Check-in | Reference required | Check-in | REFERENCE |
| 09 | Room | Reference required | Room | REFERENCE |
| 10 | Live Game | Reference required | Round | REFERENCE |
| 11 | Between Games | Reference required | Score | REFERENCE |
| 12 | Results | Reference required | Leaderboard | REFERENCE |

## Coordinator

Not started. Screens to be listed when references are supplied.

| # | Screen | Visual | Data | Status |
|---|---|---|---|---|
| — | — | — | — | — |

## Admin

Not started. Screens to be listed when references are supplied.

| # | Screen | Visual | Data | Status |
|---|---|---|---|---|
| — | — | — | — | — |

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
| Orange knight | `public/brand/knight-orange.webp` | 04 |

Awaiting supply: `recess-wordmark.svg` and `brush-pink.svg`. Both are
approximated in `src/components/brand/RecessWordmark.tsx` until then — see
the note in that file.
