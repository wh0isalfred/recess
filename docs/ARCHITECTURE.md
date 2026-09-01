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
  position int, capacity int,
  unique (event_id, label)
)

room_memberships (
  id, event_id, room_id, registration_id,
  assigned_at, left_at
)
-- No unique (room_id, registration_id): it would forbid Room 01 -> Room 02 ->
-- Room 01, which is legitimate history.
-- The rule is the partial unique index on (event_id, registration_id)
-- where left_at is null: at most one ACTIVE membership per player per event.

coordinator_assignments (
  id, event_id, user_id,
  room_id  null,              -- null = event-wide coordinator
  unique (event_id, user_id, room_id)
)
```

Rooms are **containers defined before the event** (Alfred plans two rooms in the Overview screen, §40) but **memberships are created at check-in** (§11). That resolves what reads like a contradiction in the bible: the room exists, it's just empty until people show up.

**Assignment strategy (Phase 6).** Sequential fill by room position: consider rooms in ascending `position`, assign to the first with available capacity, fill Room 01 before Room 02 begins, never exceed `rooms.capacity`. **Check-in order sets priority**, not registration order or player number. Assignment is incremental rather than a one-shot shuffle, and concurrency-safe — lock the room row, count active memberships, insert under that lock — so two simultaneous check-ins cannot claim the same final slot.

If every room is full the player stays checked in and unassigned. **`WAITING_FOR_ROOM` is derived, never stored**: checked in with no active membership row. A stored flag would be a second source of truth that can disagree with the memberships table. Admins can then raise a capacity, open another room, or assign by hand.

Reassignment preserves history — set `left_at`, insert a new row — so "which room was I in during round 2" stays answerable, and `Room 01 → Room 02 → Room 01` is valid.

**Two capacities, never conflated.** `rooms.capacity` is how many players belong to a RECESS room. `event_games.room_capacity` is one game's lobby limit. A room of 20 playing a game that caps at 15 is legitimate — the room plays in shifts — so this is deliberately **not** a cross-table database constraint; Phase 9 Live Control warns about it instead.

Because sequential fill cannot fill a room with no bound, **every room must have a positive capacity before the event may enter `CHECK_IN`**. That is enforced as a precondition of the state transition rather than a column constraint, so a room under construction can still be saved.

### 1.5.1 Game-specific aliases

A player's name inside an external game is often not their RECESS alias, and a
coordinator reading `alfred2009` in an Among Us lobby needs to know who that is.

```sql
game_aliases (
  id, event_id, registration_id, event_game_id,
  alias, created_at, updated_at,
  unique (registration_id, event_game_id)
)
-- plus unique index on (event_game_id, lower(alias))
```

Owned by `(registration_id, event_game_id)` — the only key where the database
can guarantee the game is actually being played at this event. Composite FKs to
`event_registrations (id, event_id)` and `event_games (id, event_id)` make a
cross-event alias structurally impossible.

Two players cannot claim the same external name in one game slot: that puts the
coordinator back to guessing, which is what the table exists to stop. Comparison
is case-insensitive, storage is exactly as typed. Scope is the event game, not
the room, because rooms do not exist until check-in and aliases are collected
before that.

The charset is deliberately looser than `event_registrations.alias` — external
games allow spaces and punctuation (`Big Al`), a RECESS identity does not.

**The row is mutable, and history lives in the audit log.** An alias is a lookup
key, not a competition record: a wrong result changes who won, a wrong alias
makes a coordinator squint. A trigger writes `game_alias.created` /
`.changed` / `.deleted` to `audit_logs`, which still answers "the result at
20:10 was entered against a different alias" without a third versioning
mechanism in the schema.

### 1.5.2 WhatsApp groups

Two levels, both nullable, both validated as WhatsApp group invite URLs by the
shared `is_whatsapp_group_url()` function:

- `events.whatsapp_group_url` — the main group, joined at registration.
- `rooms.whatsapp_group_url` — the room's group, revealed after assignment.

RECESS stores and later reveals the link. It manages no memberships and talks
to no WhatsApp API.

A missing room link is deliberately **not** a `CHECK_IN` precondition. A room
with no link still functions — the coordinator pastes it into the main group.
Room capacity is different, because sequential fill genuinely cannot run
without it. The general rule: a precondition exists when the software cannot
proceed, not when the night would be nicer if something were filled in.
Everything in the second category is a Phase 9 readiness warning.

Exposure follows the existing derived model with no extra columns: the link is
reachable through the active `room_memberships` row, so a player in
`WAITING_FOR_ROOM` has no active row and therefore no link, and reassignment
surfaces the new one automatically.

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

### 3.1 Templates and config shapes

**PLACEMENT** — Skribbl, trivia, Monopoly, anything ranked.

```json
{
  "type": "placement",
  "bands": [
    { "from": 1, "to": 1, "points": 10 },
    { "from": 2, "to": 2, "points": 7 },
    { "from": 3, "to": 3, "points": 5 },
    { "from": 4, "to": 4, "points": 3 },
    { "from": 5, "to": 5, "points": 2 },
    { "from": 6, "to": 10, "points": 1 }
  ],
  "unplaced_points": 0,
  "tie_rule": "SHARED_POSITION"
}
```

Payload: `{ "placements": [{ "registration_id": "...", "position": 1 }, ...] }`

`SHARED_POSITION` implements §26: two players at position 2 both receive the position-2 points, position 3 is skipped, next is 4. The alternative (`AVERAGE_BAND`, splitting the 2nd and 3rd values) is left in the enum but not built for v1.

**ROLE_OUTCOME** — Among Us.

```json
{
  "type": "role_outcome",
  "roles": [
    { "key": "crewmate", "label": "Crewmate", "is_default": true },
    { "key": "impostor", "label": "Impostor" }
  ],
  "composition": {
    "impostor": { "min": 1, "max": 3, "default": 3 }
  },
  "awards": {
    "crewmate": { "win": 2, "loss": 0 },
    "impostor": { "win": 4, "loss": 0 }
  }
}
```

Payload: `{ "winning_role": "impostor" }`

**The engine records roles; it never assumes their composition.** `composition` lives in `event_games.scoring_config`, so an event can run 1, 2 or 3 impostors and the coordinator screen adapts its validation to whatever that edition configured. `is_default: true` means every participant not explicitly assigned a role is a crewmate — which is exactly the coordinator's mental model: tick the impostors, everyone else is crew.

Keeping composition out of the engine is what makes ROLE_OUTCOME reusable for Werewolf, Mafia, or any hidden-role game later without touching scoring code.

Locked for RECESS #1: crewmate win +2, impostor win +4, loss 0, DNP 0, 3 impostors by default. The asymmetry is a judgment about how much Among Us should move the championship, not an arithmetic consequence of team size — revisit after the dress rehearsal if Among Us starts dominating.

**TEAM_OUTCOME** — `role_key` doubles as team key.

```json
{ "type": "team_outcome", "teams": [...], "awards": { "win": 5, "loss": 0, "draw": 2 } }
```

**INDIVIDUAL_OUTCOME** — chess, 8-ball, 1v1.

```json
{ "type": "individual_outcome", "awards": { "win": 5, "loss": 0, "draw": 2 } }
```

Payload: `{ "pairings": [{ "winner": "...", "loser": "..." }] }`

**MANUAL** — the escape hatch.

Payload: `{ "entries": [{ "registration_id": "...", "points": 3, "note": "improvised tiebreak" }] }`

Build MANUAL first. It is the least interesting template and the one most likely to save the night.

### 3.2 Submission is a single transactional function

```sql
submit_result(
  p_round_id        uuid,
  p_payload         jsonb,
  p_idempotency_key text
) returns jsonb
```

Inside one transaction:

1. Lock the round. Reject unless status is `LIVE`.
2. If `p_idempotency_key` already exists in `results`, return the existing outcome unchanged. **This is what makes the double-tapped `IMPOSTORS WON` button safe** (§62). The key is generated client-side when the coordinator opens the result screen, not when they tap.
3. Validate the payload against the template and the round's participants. A placement referencing someone who is DNP is a rejection, not a silent skip.
4. Void any existing non-voided `RESULT` transactions for this round.
5. Compute points from `event_games.scoring_config` and insert one `point_transactions` row per affected player. DNP players get no row at all — zero is the absence of a transaction, which keeps the ledger honest.
6. Set round status `COMPLETE`.
7. Write the audit row.
8. Bump `events.state_version`.

Returns a preview-shaped object the coordinator UI shows as the confirmation screen (§21):

```json
{ "winning_role": "impostor", "awards": [ { "alias": "DAVO", "points": 3 }, ... ] }
```

Correction (§23, §63) is the same function with a new payload and a new idempotency key. Because step 4 voids before step 5 inserts, and it is all one transaction, RECESS is never half-corrected. The admin correction screen calls `preview_result()` — the same computation with the write path skipped — to render the CURRENT / NEW / SCORE CHANGES diff before committing.

A void round (§30, crashed game) simply has all its transactions voided and status set `VOID`; a new round with the next index is created. Confirmed rounds are untouched.

### 3.3 Everything runs server-side

The client never computes a point total that anyone acts on. It may optimistically render `+3` after a coordinator confirms, but the number that lands in the standings comes back from the database. This is not paranoia about cheating — it is that two coordinators on flaky mobile data will otherwise produce two different leaderboards.

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
