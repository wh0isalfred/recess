# RECESS — Architecture

Engineering source of truth. Read alongside `docs/PRODUCT.md` for why, and
`docs/ROADMAP.md` for when.

---

## 0. Status

This is the engineering source of truth: how RECESS is built. **Build order
lives in `docs/ROADMAP.md` and nowhere else.** An earlier version of this
document carried its own phase plan; it has been removed to avoid two
competing sequences.

Locked decisions carried forward:

- Among Us: crewmate win +2, impostor win +4, loss 0, DNP 0. Impostors
  configurable 1-3, default 3.
- Every room completes the same number of scored rounds for a room-based game.
- Ties share the position; the next position is skipped.

## 1. Domain model

Postgres. Relational, as the bible insists. JSON is used for scoring configuration and result payloads only — never for relationships, never for anything you need to rank, sum or join.

### 1.1 Identity

```sql
-- A human, across all editions of RECESS. Created at first registration.
players (
  id                uuid pk,
  phone_e164        text unique not null,   -- canonical identity key
  real_name         text not null,
  canonical_alias   text,                   -- last alias used; suggested on return
  first_seen_at     timestamptz,
  created_at        timestamptz
)

-- Admins and coordinators. Backed by Supabase auth.users.
staff_profiles (
  user_id  uuid pk references auth.users,
  name     text,
  role     staff_role not null   -- SUPER_ADMIN | EVENT_ADMIN | COORDINATOR
)
```

`players` exists in v1 even though career history (§35) is deferred. It costs nothing now and it is the thing that makes §35 possible later. Phone number is the identity key because it is the one stable handle RECESS already collects.

### 1.2 Events

```sql
events (
  id, slug unique, name,
  status                  event_status,  -- see §2
  starts_at               timestamptz,
  timezone                text,          -- 'Africa/Lagos'
  registration_opens_at, registration_closes_at,
  checkin_opens_at,      checkin_closes_at,
  capacity                int,
  whatsapp_group_url      text,
  leaderboard_visibility  leaderboard_visibility default 'BETWEEN_GAMES',
  results_published_at    timestamptz,
  created_by, created_at
)
```

All timestamps stored UTC, rendered in the event's timezone. WAT has no DST, which removes the usual class of bug, but store UTC anyway — the second edition might not be in Lagos.

### 1.3 Registration

```sql
event_registrations (
  id                uuid pk,
  event_id          references events,
  player_id         references players,
  alias             text not null,        -- the RECESS identity for this edition
  player_number     int not null,
  status            registration_status,  -- REGISTERED | WAITLISTED | CANCELLED
  checked_in_at     timestamptz,
  auth_user_id      uuid,                 -- anonymous Supabase user, see §4
  created_at,

  unique (event_id, player_id),
  unique (event_id, lower(alias)),
  unique (event_id, player_number)
)
```

Player number is allocated per event by a sequence-in-a-transaction, not `count(*) + 1`. Two people registering in the same second must not both get `#024`.

Alias uniqueness is per event and case-insensitive. If someone takes `WH0ISALFRED` in September, it is free again in October — but the returning-player flow should offer them their previous alias first.

### 1.4 Games

```sql
-- The permanent library (§17). Reusable across editions.
games (
  id, slug unique, name, description,
  icon_url,
  platform              game_platform,   -- BROWSER | INSTALL | NATIVE
  platform_url          text,
  requires_install      bool,
  min_players, max_players,
  scoring_template      scoring_template,
  default_scoring_config jsonb,
  default_round_count   int,
  instructions          text,
  status                game_status       -- ACTIVE | ARCHIVED
)

-- A game placed inside one edition. Defaults are COPIED here at add time (§17).
event_games (
  id, event_id, game_id,
  position          int,        -- running order
  display_name      text,       -- optional override
  scoring_template  scoring_template,
  scoring_config    jsonb,
  planned_rounds    int,
  room_capacity     int,        -- may differ from event capacity (§14)
  status            event_game_status,  -- PENDING | LIVE | COMPLETE | SKIPPED
  started_at, ended_at,
  unique (event_id, position) deferrable initially deferred
)
```

The copy-on-add rule in §17 is the important part. An organizer tweaking Among Us scoring in September must not silently change what October inherits. `SAVE AS NEW DEFAULT` is an explicit write back to `games.default_scoring_config`, with an audit entry.

### 1.5 Rooms

```sql
rooms (
  id, event_id, label,        -- 'ROOM 01'
  position int, capacity int, -- capacity: 1-15 inclusive (Phase 6.5), includes the coordinator's seat
  unique (event_id, label)
)

room_memberships (
  id, room_id, registration_id,
  assigned_at, left_at,
  unique (room_id, registration_id)
)
-- plus: partial unique index on (event_id, registration_id) where left_at is null,
--       enforced via a denormalised event_id column on room_memberships

coordinator_assignments (
  id, event_id, user_id,
  room_id  null,              -- null = event-wide coordinator
  unique (event_id, user_id, room_id)
)

-- Phase 6.5: the REAL room coordinator is a registrant, not a staff account.
-- coordinator_assignments (above) still exists, unchanged, for a distinct
-- event-wide STAFF concept this phase does not touch or replace.
room_coordinators (
  id, event_id, room_id, registration_id,
  assigned_at, replaced_at null,   -- history preserved; replacement never deletes
  unique (room_id) where replaced_at is null,               -- one active coordinator per room
  unique (event_id, registration_id) where replaced_at is null  -- can't coordinate two rooms at once
)
```

Rooms are **containers defined before the event** (Alfred plans two rooms in the Overview screen, §40) but **memberships are created at check-in** (§11). That resolves what reads like a contradiction in the bible: the room exists, it's just empty until people show up.

Room assignment is incremental, not a one-shot shuffle. Late arrivals (§12) get assigned into whichever room has headroom under the *current* game's `room_capacity`; if none does, they hold until the next game.

**Coordinator seat reservation (Phase 6.5).** The Admin picks a room's coordinator from a real registrant — someone registered for the event, not waitlisted or cancelled, not yet checked in, and not already coordinating another room — at the moment the room is created (`admin_create_room()`, atomic: a room can never exist without a coordinator). Because that coordinator hasn't checked in yet, one seat of the room's capacity is reserved for them: `check_in_player()`'s sequential-fill loop computes, per room, whether an active `room_coordinators` row exists whose registration has no active membership in that room yet, and if so treats that room's *effective* ordinary capacity as `capacity - 1` for that check-in. The reservation is derived, not a stored flag — the moment the coordinator's own membership row exists, the same computation naturally stops reserving it. When the coordinator themselves checks in, `check_in_player()` detects the active assignment before ever entering the sequential-fill loop and assigns them directly to their own room, consuming the reserved seat — they never compete for, or wait behind, ordinary players.

**Per-room game progression (Phase 6.5).**

```sql
room_event_games (
  id, event_id, room_id, event_game_id,
  status        room_game_status,   -- PENDING | LIVE | COMPLETE
  started_at, ended_at,
  unique (room_id, event_game_id),
  unique (room_id) where status = 'LIVE'   -- one live game per room, enforced
)
```

All rooms follow the same configured `event_games` order, but rooms progress through it independently — Room 01 may be on Skribbl while Room 03 is still finishing Among Us (EVENT-OPS.md §4/§13). `event_games.status` describes the event's *configured* game; `room_event_games` describes one room's *actual progress* through it — the two are deliberately separate rather than overloading one status column with two meanings. Rows are created lazily by `start_room_game()`, not pre-seeded for every room×game combination. `start_room_game()` enforces both invariants a direct write could otherwise violate only by convention: no two games LIVE at once in the same room (the partial unique index above), and normal progression cannot skip the configured order (the immediately preceding configured game, if one exists, must already be `COMPLETE` for that room). Authorization (`is_authorized_for_room()`) admits either an event admin or that specific room's currently active coordinator — never a bare client-supplied room id.

**Game duration (Phase 6.5).** `event_games.duration_minutes` (nullable until Admin configures it, same treatment as `rooms.capacity`) and `games.default_duration_minutes` (a safe, optional library default, copied in at attach time exactly the way `default_round_count` already copies into `planned_rounds`). Minutes, not seconds — every duration this schema or EVENT-OPS.md discusses is phrased in whole minutes, and nothing about a game window needs sub-minute precision. This is configuration the coordinator's timer will read from later; `start_room_game()` records *when* a room's game started, but does not itself enforce the duration — EVENT-OPS.md §5 is explicit that expiry does not automatically end an active round.

### 1.6 Rounds and participation

```sql
rounds (
  id, event_game_id,
  room_id     null,        -- null = a whole-event round, e.g. the trivia finale
  index       int,         -- 1, 2, 3...
  status      round_status, -- DRAFT | LIVE | COMPLETE | VOID
  started_at, ended_at,
  unique (event_game_id, room_id, index)
)

round_participants (
  id, round_id, registration_id,
  participation participation_state,  -- PARTICIPATING | DNP
  role_key      text null,            -- 'impostor' | 'crewmate' | 'red' | 'blue'
  unique (round_id, registration_id)
)
```

One deliberate decision: **DNP is only stored for people who were in the room and didn't play.** A player who arrives at 8:40 does not get DNP rows retroactively written for rounds they were never eligible for. The "Skribbl — DNP / Among Us R1 — DNP" screen in §12 is *derived* at render time from the games that completed before their check-in time. Storing it would mean writing history for a person who wasn't there, and it would break the moment someone's check-in is corrected.

### 1.7 Results and the ledger

```sql
results (
  id, round_id unique,
  template          scoring_template,
  payload           jsonb,          -- shape depends on template, see §3
  submitted_by      uuid,           -- staff user
  submitted_at      timestamptz,
  idempotency_key   text unique,
  version           int default 1
)

point_transactions (
  id, event_id, registration_id,
  points            int,
  source            transaction_source, -- RESULT | MANUAL_ADJUSTMENT
  result_id         null references results,
  round_id          null,
  event_game_id     null,
  note              text,
  voided_at         timestamptz,     -- corrections void, never delete
  created_by, created_at
)

audit_logs (
  id, event_id,
  actor_user_id, action, entity_type, entity_id,
  before jsonb, after jsonb, created_at
)
```

`player.total_points` does not exist as a stored column (§24). Standings are a view:

```sql
create view event_standings as
select
  r.event_id, r.id as registration_id, r.alias,
  coalesce(sum(pt.points) filter (where pt.voided_at is null), 0) as points,
  rank() over (
    partition by r.event_id
    order by coalesce(sum(pt.points) filter (where pt.voided_at is null), 0) desc
  ) as position
from event_registrations r
left join point_transactions pt on pt.registration_id = r.id
where r.status = 'REGISTERED'
group by r.event_id, r.id, r.alias;
```

`rank()` — not `dense_rank()` — gives exactly the competition ranking §26 asks for: 1, 2, 2, 4.

Corrections **void** transactions rather than deleting them. The ledger stays append-only, which means the audit trail and the correction history are the same artifact, and a player detail screen can honestly show what changed.

### 1.8 Awards

```sql
awards (id, event_id, name, description, icon_url, is_competitive bool default false)
award_recipients (id, award_id, registration_id, note, unique (award_id, registration_id))
```

`is_competitive` exists so the schema itself enforces §34: awards never write to `point_transactions`. Culture and competition stay separate structurally, not just by convention.

---

## 2. Event state

```
DRAFT → REGISTRATION → REGISTRATION_CLOSED → CHECK_IN → LIVE → COMPLETE
                                                          ↕
                                                       PAUSED
any → CANCELLED
```

Transitions are a database function, not an `UPDATE` from the client:

```sql
transition_event(event_id, to_status) returns events
```

It validates the transition is legal, checks preconditions, writes the audit row, and bumps `events.state_version`. Preconditions worth enforcing: you cannot go `LIVE` with zero checked-in players; you cannot go `COMPLETE` with a round still `LIVE`; `PAUSED` can only return to `LIVE`.

### The player view is derived, never assembled client-side

This is the architectural key to "one interface that changes as the night progresses" (§5, §31).

One server function returns the player's entire current state as a tagged union:

```sql
get_player_state(registration_id) returns jsonb
```

```json
{
  "view": "LIVE_ROUND",
  "event": { "name": "RECESS — September", "status": "LIVE" },
  "player": { "alias": "WH0ISALFRED", "number": 24 },
  "room": { "label": "ROOM 03" },
  "current_game": { "name": "Among Us", "round": 1, "of": 4, "status": "LIVE" },
  "standing": { "position": 12, "points": 8, "visibility": "BETWEEN_GAMES" },
  "actions": []
}
```

Views: `LANDING`, `REGISTRATION_CLOSED`, `PASS_COUNTDOWN`, `CHECK_IN_OPEN`, `CHECKED_IN_WAITING`, `LATE_ARRIVAL`, `ROOM_ASSIGNED`, `LIVE_ROUND`, `BETWEEN_GAMES`, `PAUSED`, `RESULTS`.

The React app renders whichever view comes back. It contains no rules about which screen to show. Leaderboard visibility is applied *inside* this function — a HIDDEN_UNTIL_FINALE event genuinely does not send other players' points to the client, rather than hiding them in CSS.

---

## 3. Scoring engine

**This section describes what Phase 7 actually built.** An earlier draft of
this section (fixed per-position point bands for PLACEMENT, Among Us at
crewmate +2/impostor +4, point transactions written per round) predates the
locked RECESS #1 rules in `docs/SCORING.md` and no longer matches either
that document or the implementation below — the numbers and the mutation
shape it described were both superseded before Phase 7 began.

### 3.1 The three layers map onto existing objects

SCORING.md's separation — RAW PERFORMANCE → GAME PLACEMENT → RECESS
CHAMPIONSHIP POINTS — maps directly onto tables that already existed,
mostly unused, from Gate A:

- **Raw performance** lives in `results.payload`, one row per round,
  immutable and append-only via the supersession chain already built in
  0009 (`superseded_at`/`superseded_by`, one non-superseded result per
  round enforced by a partial unique index). `round_participants` (also
  0008) is the per-round record of who did what: `participation`
  (PARTICIPATING/DNP), `role_key` (free text — ROLE_OUTCOME never hardcodes
  role names into schema), and `raw_score` (Phase 7, PLACEMENT only — a
  round's external-platform score per participant).
- **Game placement** is never stored. It is computed at settlement time by
  ranking the aggregated raw totals.
- **RECESS championship points** land in `point_transactions` (0009) — but
  only once per room-game, at settlement, never per round.

### 3.2 Templates actually implemented: PLACEMENT and ROLE_OUTCOME

**PLACEMENT** — Skribbl, Trivia. `event_games.scoring_config` needs nothing
beyond `{"type": "placement"}` (present only so the existing
`transition_event()` check-in guard, which refuses to open check-in while
any game has an empty `{}` config, has something to see). There are no
per-game point bands: every game's final ranking normalizes onto the same
0–20 scale via one universal formula (§3.4), so a placement game's raw
score only ever needs to be summed and ranked, never converted through a
game-specific curve.

**ROLE_OUTCOME** — Among Us. `scoring_config` carries `awards`, keyed by
role, e.g. `{"crewmate": {"win": 1, "loss": 0}, "impostor": {"win": 2,
"loss": 0}}` — the locked RECESS #1 values (SCORING.md §6). The engine
reads whichever roles a payload's `winningRole` and each participant's
`role` actually name; it never assumes two, or any fixed number, of
impostors. Composition (1–3 impostors) is a coordinator-facing concern this
phase does not build UI for — the engine only needs a role key and that
key's configured win/loss award.

TEAM_OUTCOME, INDIVIDUAL_OUTCOME, and a UI for MANUAL remain unimplemented;
`admin_manual_adjustment()` (the ledger-level escape hatch) is built.

### 3.3 Round lifecycle and settlement are two different operations

```sql
start_round(p_room_id, p_event_game_id) returns jsonb
```
Snapshots every registration with an active `room_membership` in that room
at that exact moment into `round_participants`. A player who joins later is
simply not in that snapshot — EVENT-OPS.md §7 — and becomes eligible
starting with the next call to `start_round`.

```sql
preview_round_result(p_round_id, p_payload) returns jsonb
submit_round_result(p_round_id, p_payload, p_idempotency_key) returns jsonb
```
Both share one validator (`validate_round_payload`) that checks every
payload entry against the round's own snapshot — a registration not in it
is rejected, not silently ignored — and against the event-game's configured
roles. Preview runs this and returns the facts it would record; nothing is
written. Submit does the same validation, then writes: supersede any
existing result for this round (correction), insert the new one, update
`round_participants` to match, mark the round `COMPLETE`. The idempotency
key is globally unique on `results` — a repeated key returns the original
outcome unchanged, whether that's the first tap or the fifth.

**Round confirmation does not write to the point ledger.** A room-game is
settled — raw totals aggregated across every confirmed round, ranked,
normalized, and turned into `point_transactions` — exactly once, when
`complete_room_game()` (0021, extended here to trigger this) runs. This is
literally where SCORING.md §10 places it: "the room-game is settled when
the coordinator completes that game." `complete_room_game()` also now
refuses to complete while any round for that room-game is still `LIVE`.

A correction to a round belonging to an *already-settled* room-game
re-settles immediately, inside the same transaction as the correction —
SCORING.md §13's numbered steps (supersede → recompute → void old
transactions → write replacements) are not a separate manual process. The
previous settlement's transactions are identified by
`point_transactions.room_event_game_id` (Phase 7's one new ledger column) —
a stable key naming *which room's settlement of which game* produced them,
robust regardless of which specific round's correction triggered the
re-settlement.

```sql
void_round(p_round_id, p_reason) returns jsonb
```
Only a `LIVE` round can be voided — EVENT-OPS.md §16, the crashed-game
case. A `COMPLETE` round's fix path is correction (submit again), not
voiding.

### 3.4 Normalization is a fixed formula, not configuration

For a settled room-game with N ranked players (everyone who participated in
at least one confirmed round — a full-game DNP never enters this set) and a
player's competition placement P:

```
RECESS_POINTS = round(20 × (N - P) / (N - 1))     for N >= 2
RECESS_POINTS = 20                                 for N == 1
```

This is the same formula for every template, every game, every room — it
is not read from `scoring_config`, and no per-game bands exist to override
it. First place is always 20; the last ranked place is always 0; ties use
competition ranking (1, 2, 2, 4) with no hidden tiebreaker.

### 3.5 Standings and qualification are read, never stored

```sql
room_standings(p_room_id) returns jsonb
```
Sums each room member's non-voided `point_transactions`, ranks the totals,
and marks `qualifies` for positions 1–2 (RECESS #1's locked value; the
count itself stays a parameter, not a hardcoded `<= 2`) — including
everyone tied into position 2. Nothing about a player's standing or
qualification is stored as independent mutable truth; both are recomputed
from the ledger on every read, which is what makes a correction's
"recompute standings, recompute qualification" (SCORING.md §13) automatic
rather than a separate step this schema would otherwise need to remember
to perform.

### 3.6 Everything still runs server-side

Unchanged from the original framing here: the client never computes a
point total anyone acts on. Every number above comes back from one of the
functions in this section, computed inside a single transaction, or it
doesn't exist yet.

---

## 4. Authorization

### 4.1 Staff

Supabase Auth, email + password (or magic link). `staff_profiles.role` drives RLS. Coordinator scope is `coordinator_assignments` — a coordinator can read and write only rounds whose `room_id` they are assigned to, and only for the event's currently `LIVE` event_game.

Every permission in §22 is an RLS policy or a check inside a `security definer` function. Hiding a button in React is not a permission.

### 4.2 Players — the honest answer to §59

The bible wants no passwords, RLS-protected data, and realtime. Those three together are the tricky part, because Supabase Realtime authorises on a JWT.

Two workable options:

**A. Supabase anonymous sign-in (recommended).** On registration, call `signInAnonymously()`, store `auth.uid` on the registration row. The player gets a real JWT, so RLS and Realtime work with no custom infrastructure. Session persists in the browser. No password anywhere.

**B. Custom JWT.** Mint a token server-side signed with the project JWT secret, carrying the registration id. More control, more code, more ways to get signing wrong under time pressure.

Take A for September.

The failure mode of A is real and worth naming: **a player who clears their browser, or opens the link in WhatsApp's in-app browser and then again in Chrome, loses their pass.** Given the entire distribution channel is WhatsApp, this will happen to someone on the night.

Recovery for v1: a `/recover` route taking phone number + player number, rate-limited to 5 attempts per number per hour, which re-links a fresh anonymous session to the existing registration and writes an audit row. It is not perfectly secure — someone who knows your number and saw your player number could take your pass — but the asset being protected is a place on a leaderboard at a game night, and the alternative is a player locked out at 8:15pm. Note the trade-off, ship it, revisit if RECESS ever carries prizes worth stealing.

Sequential IDs are never routes. `/pass` reads the session; there is no `/player/24`.

---

## 5. Routes

```
Player (mobile-first, no bottom nav)
  /                          landing → redirects to /pass if a session exists
  /register                  3 steps, client-routed, one URL
  /pass                      the state machine surface — countdown, check-in,
                             room, live, results all render here
  /recover
  /r/:eventSlug              public results, shareable, no session needed

Coordinator (mobile-first, authed)
  /c                         my assignments
  /c/:roomId                 roster, rounds, result submission

Admin (desktop-first, responsive)
  /admin
  /admin/events
  /admin/events/:id/overview
  /admin/events/:id/roster
  /admin/events/:id/games
  /admin/events/:id/rooms
  /admin/events/:id/live
  /admin/events/:id/leaderboard
  /admin/events/:id/awards
  /admin/events/:id/settings
  /admin/games               library        [October]
  /admin/players             cross-event    [October]
```

`/pass` being a single route matters. It is not a set of pages the player navigates between; it is one surface the night moves through. Back-button behaviour stays sane and there is nothing to get lost in.

---

## 6. Realtime

The temptation is to subscribe the client to `point_transactions` and let it recompute. Don't — that leaks other players' scores past the visibility rules and puts scoring logic back in React.

**Broadcast a nudge, fetch the truth.**

- One channel per event: `event:{id}`.
- The server broadcasts small signals: `{ type: "state", version: 42 }`.
- On receipt, each client refetches `get_player_state()` (players) or its relevant slice (admin, coordinator).
- Signals fire on: event status change, event_game status change, round start/complete/void, room assignment, results publication.

The payload carries no scores. A player on a HIDDEN_UNTIL_FINALE event receives the same nudge as everyone else and gets back a state object with no standings in it.

Cost: one extra round trip per update. Benefit: authorisation lives in one function instead of in RLS policies on five tables, and the client cannot desynchronise from the server's view of the night.

Reconnection: on `SUBSCRIBED` after any disconnect, always refetch. Phones will sleep; WhatsApp will foreground and background the browser repeatedly. Assume every client is stale on every resume.

Also poll `get_player_state()` every 30s as a floor. Realtime will drop for someone in Port Harcourt on the night, and a 30-second stale screen is survivable where a permanently frozen one is not.

---

## 7. Design system

Moved to `docs/BRAND.md`, which is now the single place tokens, typography,
texture, motion and platform rules are defined. Two token tables in two files
is exactly how they drift apart.

The engineering constraint that stays here: brand values live in
`src/styles/tokens.css` as CSS custom properties. Tailwind consumes them via
the `@theme inline` block in `src/app/globals.css`. Components use named
utilities (`bg-pink`, `text-fg`,
`min-h-tap`), never arbitrary values. ESLint blocks raw hex.

## 8. Risks and contradictions

**1. Ten days.** Covered in §0. The largest risk by a distance.

**2. Cross-room placement is not fair, and someone will notice.** [LOCKED: every room plays the same number of scored rounds.] First place in a 13-player Skribbl room and first place in a 12-player room both pay 10. If one room finishes three Among Us rounds and the other finishes four, the second room's players earn more purely by being in the faster lobby. Mitigations, cheapest first: lock rounds-per-game and have Live Control refuse to advance until every room has submitted the same number; or normalise placement points by room size. For September, do the first — it is an operational rule, not code — and put a warning in Live Control when room round counts diverge.

**3. Role assignment luck dominates Among Us scoring.** [LOCKED for RECESS #1: crew win +2, impostor win +4, loss 0, DNP 0, impostor count configurable 1–3, default 3.] Re-check after the dress rehearsal.

**4. Anonymous sessions and WhatsApp's in-app browser.** See §4.2. Expect at least one recovery on the night; make sure `/recover` is tested on an actual phone, in the actual WhatsApp browser.

**5. Coordinators on mobile data.** Result submission must be a queued write with visible pending state and retry, not a fire-and-forget POST. The idempotency key makes retries safe. Without this, a coordinator taps CONFIRM, sees nothing, taps again, and only trusts the app if it was built to handle exactly that.

**6. Rooms formed at check-in vs planned before.** Resolved in §1.5 — rooms are containers, memberships are assignments.

**7. Late-arrival DNP.** Resolved in §1.6 — derived, not stored.

**8. Ties on a shared prize.** §26 says tied players split the prize. Nothing in the schema handles money, and it shouldn't. This is a rule Alfred announces, not a feature.

**9. Leaderboard visibility must be server-enforced.** Done via `get_player_state()`. Worth stating explicitly because the natural implementation is a client-side conditional, which leaks over the network.

**10. Total failure plan.** If the app is down at 8:30pm, the night must continue. Coordinators record results in WhatsApp; Alfred backfills afterwards through MANUAL transactions. Say this out loud to the coordinators beforehand so nobody freezes. The point of RECESS is the evening, not the software.

---

## 9. Separation of concerns

```
/db/migrations        schema, enums, views
/db/functions         transition_event, get_player_state,
                      submit_result, preview_result, assign_rooms
/src/domain           TypeScript types generated from the schema; scoring
                      config validators; state-machine types. No React.
/src/server           route handlers, auth, RLS-aware queries
/src/realtime         channel subscription, reconnect, refetch
/src/design           tokens, Surface, primitives
/src/features         player/, coordinator/, admin/ — composition only
```

The rule that keeps this honest: **`/src/features` contains no arithmetic.** If a component computes a point value, a rank, or a state decision, it belongs in the database or in `/src/domain`. That single constraint is what stops RECESS becoming a React app with a competition buried in it.

---

## Open items

1. **Placement scoring values for RECESS #1.** Simplification agreed, numbers not yet given. Seeded with the bands in §3.1 as a placeholder; changing them is one line of SQL.
2. **Event capacity.** Seeded at 30 with two rooms of 15, which is internally consistent with Among Us's 15-per-lobby limit. The 60 in the admin mockup would require four parallel Among Us lobbies and four coordinators.
