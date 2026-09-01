# RECESS — Build Roadmap

## The operating rule

> **Claude: Work on ONE phase at a time.**
>
> Do not begin work belonging to a future phase, even if it seems convenient
> while implementing the current one.
>
> At the end of each phase:
>
> 1. Run the relevant tests and checks.
> 2. Verify the acceptance criteria.
> 3. Summarize exactly what was built.
> 4. List files/database objects created or changed.
> 5. State any deviations, unresolved problems, or decisions required.
> 6. STOP.
>
> Wait for explicit approval before beginning the next phase.
>
> Do not use a future phase to hide unfinished work from the current phase.

That is the most important instruction in this document.

The build order is deliberately **foundation → domain → design system →
landing → registration → pass → attendance → scoring → operations → realtime
→ results**. Each layer has something stable beneath it.

---

## Phase 0 — Repository & Project Foundation

**Goal.** Turn the empty GitHub repository into a correctly structured RECESS
application.

**Build.** Next.js, TypeScript, Tailwind CSS, Supabase, ESLint, environment
configuration, project directory structure. Documentation structure:
`README.md`, `CLAUDE.md`, `docs/PRODUCT.md`, `docs/ARCHITECTURE.md`,
`docs/BRAND.md`, `docs/ROADMAP.md`, `docs/EVENT-OPS.md`. Initial design
tokens: paper, paper-deep, ink, aubergine, aubergine-lift, pink, pink-deep,
amber. Only the primitives we already know we need: `Surface`, `Button`,
`Field`.

**Do not build.** No registration. No admin. No scoring. No Event Pass. No
rooms. No games. No fake dashboards. No giant component library.

**Acceptance.** `npm run dev` works. Production build works. Supabase clients
initialize correctly. Environment secrets aren't committed. Basic cream and
aubergine `Surface` examples render correctly.

**STOP.**

---

## Phase 1 — Database & Domain Foundation

Comes before the pretty player screens.

**Goal.** Give RECESS its data model: `players`, `staff_profiles`, `events`,
`event_registrations`, `games`, `event_games`, `rooms`, `room_memberships`,
`coordinator_assignments`, `rounds`, `round_participants`, `results`,
`point_transactions`, `audit_logs`, `awards`, `award_recipients`, plus the
enums. Relationships stay relational; JSON is reserved for configurable
scoring and result payloads.

**Important correction.** Among Us must not assume two impostors. Role Outcome
supports configurable role composition. Current config allows up to 3 — but
even 3 is configuration, not scoring-engine logic.

**Seed data.** RECESS — September 2026. Among Us, Skribbl, Trivia. Room 01,
Room 02. Seed data, not hardcoded application behaviour.

**Event lifecycle.** `DRAFT`, `REGISTRATION`, `REGISTRATION_CLOSED`,
`CHECK_IN`, `LIVE`, `PAUSED`, `COMPLETE`, `CANCELLED`, plus the controlled
transition function. Transitions are server/database-controlled, never
arbitrary client updates.

**Do not build.** No registration UI. No scoring engine. No admin UI.

**Acceptance.** We can create an event, attach games, create rooms and query
the complete structure. Invalid state transitions are rejected.

**STOP.**

---

## Phase 2 — RECESS Design System

Establish the visual language before improvising screens.

**Goal.** Translate the approved mockups into production components:
`Surface`, `Button`, `Field`, `StepIndicator`, `Ticket`, `StatBlock`,
`GameRow`, `StatusPill`, `RoundProgress`. Establish typography, responsive
spacing, radii, shadows, grain, icon treatment, and button / input / error /
loading / focus states plus reduced-motion behaviour.

**Important.** Use the supplied screens as reference. Do not redesign RECESS.
No bottom navigation. No game controllers.

**Acceptance.** A temporary internal component preview page where buttons,
inputs, ticket, typography, colours, cream and night surfaces, game rows and
statuses can all be inspected — and they visually belong to the approved
screens.

**STOP FOR VISUAL REVIEW.** This checkpoint catches ugly components before ten
screens get built with them.

---

## Phase 3 — Public Landing Experience

**Goal.** Someone opening RECESS understands it immediately. Build `/`.

Hero, the event's configured games, a how-it-works sequence (show up → get a
room → play → earn points → someone wins), and preparation requirements
(Among Us install required, Skribbl browser, Trivia browser).

Event information comes from the database. Not `const date = "September 11"`.

**States.** Registration not open, open, full, closed, event complete.

**Acceptance.** Works on small phone, normal phone, tablet, desktop. Event
information is real database data. CTA reacts correctly to registration status.

**STOP FOR DESIGN REVIEW.**

---

## Phase 4 — Player Registration

**Goal.** Visitor → RECESS player.

Three steps: name; alias with live preview; WhatsApp number. Then
`CLAIM MY SPOT →`.

**Backend.** Create or reuse player. Create event registration. Case-
insensitive alias uniqueness. Atomic player-number allocation. Capacity
enforcement. Waitlist if enabled. Prevent duplicate registration. Anonymous
player session.

**Acceptance.** Two simultaneous registrations cannot receive the same number.
Two players cannot claim the same alias for one event. Capacity cannot be
exceeded. Refresh doesn't duplicate a registration. The session survives
closing and reopening the browser.

**STOP.**

---

## Phase 5 — Event Pass

**Goal.** Registered players returning to the site enter their event
experience at `/pass`. Landing detects an existing registration and directs
them there.

Pre-event: greeting, next date, days to go, `YOU'RE IN ✓`, a GET READY list of
games with install/browser labels, and the WhatsApp CTA.

**Critical architectural rule.** `/pass` remains **one route**. We do not later
create `/pass/checkin`, `/pass/room`, `/pass/game`, `/pass/results`.

**Acceptance.** Registered player closes the browser, returns, lands in their
Event Pass. An unauthenticated visitor cannot access another person's pass.

**STOP.**

---

## Phase 6 — Check-In & Room Assignment

**Goal.** Turn registrations into attendees, then into rooms.

Rooms can exist beforehand; membership is assigned when players actually check
in. Support random assignment, room capacity, uneven rooms, late arrivals, and
manual admin reassignment later.

**Acceptance.** With 10–20 test registrations checked in in random order:
nobody exceeds room capacity; no player occupies two active rooms; assignment
survives refresh; late-player behaviour works; an unregistered player cannot
check in.

**STOP.**

---

## Phase 7 — Scoring Engine

The hardest backend piece, built in isolation, with no leaderboard UI
distractions.

**Templates.** `PLACEMENT`, `ROLE_OUTCOME`, `TEAM_OUTCOME`,
`INDIVIDUAL_OUTCOME`, `MANUAL`. The generic engine knows nothing special about
Among Us.

**Core principle.** Admins record facts. RECESS calculates consequences.

**Implement.** `submit_result()`, `preview_result()`, void result/round,
correction, point ledger, standings calculation.

**Idempotency is non-negotiable.** Tapping `IMPOSTORS WON` five times on a
lagging network still produces one result and one set of points.

**Tests.** Normal result, double submission, triple submission, correction,
DNP, tie, void round, manual adjustment, invalid participant, invalid role,
invalid placement.

**Acceptance.** Given the same event facts, scoring always produces the same
standings.

**STOP.**

---

## Phase 8 — Coordinator Experience

A mobile-first UI over the scoring engine. Coordinator home, room, roster,
current game and round. Participation ticks, role selection up to the
**configured** maximum, winner selection, result preview, confirm.

**Network failure needs serious testing.** Submitting must show `SUBMITTING…`
or `NOT SENT / RETRY →`. Never silently fail.

**Acceptance.** Run several fake games from an actual phone, toggling Wi-Fi
and mobile data during submission. No duplicated points.

**STOP.**

---

## Phase 9 — Admin Live Control

Desktop-first, responsive. One screen answering: what is happening right now?
Current game, each room's round and result status, player counts. Actions:
pause event, start next round, start next game, view leaderboard. Warnings
when rooms diverge.

**Locked fairness rule.** Every room completes the same number of scored
rounds for a room-based game.

**Acceptance.** Admin can run a simulated event without touching Supabase
manually.

**STOP.**

---

## Phase 10 — Realtime Player Experience

**Goal.** Admin or captain action → the player's Event Pass changes
automatically.

**Architecture.** Broadcast a nudge. Fetch the truth. Realtime messages say
something changed; each player refetches their authorized current state.
Refetch after reconnection; poll every 30 seconds as a safety net.

`/pass` now renders `CHECK_IN_OPEN`, `CHECKED_IN_WAITING`, `ROOM_ASSIGNED`,
`LIVE_ROUND`, `BETWEEN_GAMES`, `PAUSED`, `RESULTS`.

**Acceptance.** Multiple real phones. Start and finish rounds. Background a
phone, open WhatsApp, return. Lose network, reconnect. State recovers.

**STOP.**

---

## Phase 11 — Leaderboard & Results

Leaderboard visibility `LIVE`, `BETWEEN_GAMES`, `HIDDEN_UNTIL_FINALE`,
enforced server-side, not with CSS.

Final player result, and public results at `/r/:eventSlug` with full standings
and player breakdown. Competition ranking is `1, 2, 2, 4` — not `1, 2, 2, 3`.

**Acceptance.** Run a complete fake event. Calculate expected totals by hand,
separately. They must match RECESS exactly.

**STOP.**

---

## Phase 12 — Recovery, Failure States & Hardening

Happy-path testing is not enough for live software. Test: lost player session,
WhatsApp in-app browser, refresh during a round, coordinator loses internet,
admin refresh, duplicate submissions, double check-in, game crash, void round,
incorrect result, late arrival, player leaves, player returns, room full,
event paused, database request fails, realtime disconnect, malformed scoring
configuration.

Implement `/recover`.

**Emergency mode.** If RECESS dies during the event, the event continues.
Captains record results elsewhere; we backfill with Manual transactions. That
is event operations, not a coding failure. See `docs/EVENT-OPS.md`.

**STOP.**

---

## Phase 13 — Dress Rehearsal

No new features. Seriously.

Six to twelve people, actual phones, a compressed fake RECESS: registration,
check-in, rooms, a Skribbl result, several Among Us rounds, a Trivia result, a
late player, a deliberate disconnect, a deliberate double submission, one
deliberately wrong result that gets corrected, finish, publish standings.

Record every problem. Fix **only launch blockers**.

---

## Phase 14 — First RECESS 🚀

Stop coding. Run the night. Observe where players got confused, what
coordinators hated, what Alfred had to do manually, what broke, what nobody
used, what people asked for, how room timing actually behaved, whether scoring
felt fair, whether people cared about the leaderboard, and whether people
actually had fun.

Those observations determine v2. Not our imagination.

---

## Post-launch — RECESS 0.2

Only after we have run one.

**Admin product.** Event Builder, Game Library CRUD, roster management, room
management, scoring configuration UI, result correction UI, awards management,
coordinator management.

**Later.** Player history, past editions, career stats, returning-player
recognition, awards history, champions, shareable result cards, automated room
balancing, more sophisticated game templates.

RECESS then accumulates history and culture, rather than us manufacturing
engagement features before anybody has played.

---

## How to work with an agent on this

Not:

> "Build Phase 0–5."

But:

> Read `docs/ROADMAP.md`, `docs/PRODUCT.md`, `docs/ARCHITECTURE.md`,
> `docs/BRAND.md`, and `CLAUDE.md`. We are currently at Phase N. Implement
> Phase N only. Do not begin Phase N+1. At completion, run its acceptance
> checks, give me the phase completion report defined in ROADMAP.md, then stop.

Then inspect it. After approval:

> Phase N approved. Commit the completed state if necessary. Begin Phase N+1
> only.
