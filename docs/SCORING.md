# RECESS — Scoring

This document defines how RECESS converts performance inside different games
into one fair room competition.

The central rule is:

> Raw scores from different games are never directly added together.

4,210 Skribbl points and 8,700 Trivia points do not mean the same thing.

RECESS therefore separates:

RAW GAME PERFORMANCE
→ GAME PLACEMENT
→ RECESS CHAMPIONSHIP POINTS

---

## 1. Scoring principles

1. Every configured game contributes equally to the room championship unless an
   event explicitly changes that rule in a future version.

2. For RECESS V1, every completed game contributes a maximum of 20 RECESS
   championship points per player.

3. Raw external-game scores exist only to determine performance inside that
   game.

4. A coordinator records facts and raw scores.

5. RECESS calculates placements and championship points.

6. DNP is zero, not a loss penalty.

7. Ties share placement.

8. Championship totals are derived from immutable/auditable scoring facts.

---

## 2. Three scoring layers

### Layer 1 — Round raw performance

This is what happened inside a specific round.

Examples:

Among Us:
- role;
- winning side;
- participant status.

Skribbl:
- raw score.

Trivia:
- raw score.

---

### Layer 2 — Game performance

All confirmed rounds belonging to the same game and room are combined into the
player's raw game total.

Players are ranked inside that game.

Examples:

AMONG US

kemz        5 raw
alfred      4 raw
theo        4 raw
sarahh      2 raw

Placement:

1 kemz
2 alfred
2 theo
4 sarahh

The raw numbers do not become championship points directly.

---

### Layer 3 — RECESS championship points

Once the room completes that game, its final game ranking is normalized onto
the RECESS 0–20 scale.

Only then are championship points settled.

---

## 3. RECESS normalized points

Let:

N = number of distinct ranked players who actually participated in at least
one scored round/session of that game.

P = the player's competition placement in that game's final ranking.

For N >= 2:

RECESS_POINTS =
round(
  20 × (N - P) / (N - 1)
)

The result is rounded to the nearest whole championship point.

This means:

- first place always receives 20;
- last ranked place receives 0;
- intermediate positions are distributed across the same range;
- rooms of different sizes still award the same maximum score.

### Example — 15 ranked players

1st  = 20
2nd  = 19
3rd  = 17
4th  = 16
5th  = 14
6th  = 13
7th  = 11
8th  = 10
9th  = 9
10th = 7
11th = 6
12th = 4
13th = 3
14th = 1
15th = 0

### Example — 10 ranked players

1st  = 20
2nd  = 18
3rd  = 16
4th  = 13
5th  = 11
6th  = 9
7th  = 7
8th  = 4
9th  = 2
10th = 0

---

## 4. Who counts in N?

A player is included in the game's ranked field if they participated in at
least one confirmed scored round/session of that game.

A player who DNPs the entire game:

- receives 0 RECESS championship points for that game;
- does not expand the ranked denominator N.

A late arrival who joins and participates in a later valid round is included in
the game ranking.

This means RECESS ranks people who actually competed while still recording a
full-game DNP as zero.

---

## 5. Ties

Final game placement uses competition ranking.

Example:

1 Alfred
2 Kemz
2 Theo
4 Sarah

Kemz and Theo both use P = 2 in the normalization formula and therefore
receive exactly the same RECESS championship points.

The next placement is 4.

There are no hidden decimal scores or secret tiebreakers.

---

## 6. Among Us raw scoring

Among Us uses ROLE_OUTCOME scoring.

For RECESS V1, the default raw values are:

Crewmate win = 1 raw Among Us point
Impostor win = 2 raw Among Us points
Loss = 0
DNP/disconnect = 0

These values are NOT championship points.

They exist only to rank performance within Among Us.

Example:

Round 1:
Alfred is Crewmate and wins → +1 raw

Round 2:
Alfred is Impostor and wins → +2 raw

Round 3:
Alfred is Crewmate and loses → +0 raw

Alfred's Among Us raw total = 3.

Once all valid Among Us rounds for the room are completed, RECESS ranks the
raw totals.

That final placement is then normalized onto the 0–20 RECESS scale.

### Roles

RECESS does not assume a fixed number of impostors.

The coordinator records the actual role of each participant.

The configured game may allow 1–3 impostors.

The scoring engine cares about the role key and configured outcome values, not
about hardcoded Among Us assumptions.

---

## 7. Placement games

Skribbl and Trivia use placement scoring.

The external platform's score is stored as raw game performance.

For one-session games, that score is the player's raw game total.

If the event configures multiple scored sessions, V1 aggregates confirmed raw
scores by addition:

GAME_RAW_TOTAL =
sum(confirmed round/session raw scores)

The resulting totals are ranked.

That game placement is then converted to 0–20 RECESS championship points.

---

## 8. DNP

DNP contributes zero raw score for the missed round.

A player who participated in other rounds of the same game keeps their earlier
raw performance and remains eligible for final game placement.

A player who DNPs every scored round/session receives 0 championship points for
that game.

DNP never removes championship points already earned from an earlier completed
game.

---

## 9. Voided rounds

A voided round contributes nothing.

Its raw result must not affect:

- game totals;
- game placement;
- championship points;
- room standings.

If the game is replayed, the replacement is a new valid round/result.

---

## 10. Game settlement

Round results do not directly become final championship points when a game may
contain several rounds.

Instead, the room-game is settled when the coordinator completes that game.

Settlement performs:

confirmed round results
→ raw game totals
→ competition ranking
→ normalized RECESS points
→ championship point transactions

A room-game may have only one current authoritative settlement.

This prevents a game with three rounds from being worth three times as much as
a one-round game.

Among Us, Skribbl and Trivia are therefore each worth the same maximum:

20 RECESS points.

With three equal-weight games, the maximum room-phase total is:

60 RECESS points.

---

## 11. Room standings

Room championship standings are:

SUM(
  settled RECESS championship points
  from completed games
)

Raw scores are never added directly to this total.

Unfinished games should not constantly mutate the authoritative championship
total.

The completed-game settlement is the point at which that game's contribution
becomes official.

---

## 12. Qualification

At the end of the room phase, players are ranked by total RECESS championship
points within their room.

RECESS #1 qualifies positions 1 and 2 from every room.

The qualification count should remain configurable — RECESS #1 locks the
*value* (2), not the architecture, since the number of rooms (and therefore
how many total finalists that implies) may change between editions.

### Qualification ties

If a tie touches the qualification boundary, everybody tied at that position
qualifies.

Example:

1 Alfred
2 Kemz
2 Theo
4 Sarah

If the top 2 positions qualify:

Alfred, Kemz and Theo all qualify — the tie at 2nd means both Kemz and Theo
hold that position, and neither is bumped out to make room for the other.
Sarah, at 4, does not qualify.

No tiebreak is secretly applied.

---

## 13. Corrections

A correction changes the underlying scoring fact.

It does not manually change a player's total.

Example:

Skribbl was submitted as:

Theo = 3820

Correct value:

Theo = 3920

After Admin approval, RECESS must:

1. supersede the incorrect result;
2. create the corrected authoritative result;
3. recompute the affected game totals;
4. recompute placement;
5. recompute the room-game settlement;
6. void championship transactions produced by the old settlement;
7. create the correct replacement transactions;
8. recompute room standings;
9. recompute qualification if required;
10. create an audit entry.

Historical records remain visible.

---

## 14. Idempotency

Result submission must be idempotent.

If network lag causes the coordinator to submit the same confirmed result
multiple times, RECESS must still create:

- one authoritative result;
- one scoring effect;
- no duplicate championship points.

Every result submission uses an idempotency key.

---

## 15. Preview before confirmation

No coordinator result should go directly from form input to authoritative
scoring.

The normal flow is:

INPUT
→ VALIDATE
→ PREVIEW
→ CONFIRM

Preview shows what RECESS understood.

Examples:

Among Us:
- participating players;
- impostors;
- winning side;
- DNPs;
- raw score effect.

Skribbl/Trivia:
- submitted raw scores;
- derived placement;
- ties.

The coordinator confirms facts.

They do not confirm hand-calculated points.

---

## 16. Manual adjustments

MANUAL scoring is an emergency/admin escape hatch.

It is not part of normal coordinator flow.

A manual adjustment:

- requires Admin authority;
- requires a reason/note;
- is recorded in the point ledger;
- is visible in audit history.

Normal mistakes should be fixed by correcting the source result instead.

---

## 17. Championship round

RECESS #1 has now locked the finale shape. The room-phase scoring engine
(Scoring Engine V1) still must not hardcode any of this into room-phase
logic — qualification and room standings are computed exactly as above,
independent of what happens next — but the finale itself is no longer an
open question.

### The finale game

The championship finale is Trivia.

Every qualifier from every room (§12 — positions 1 and 2, plus anyone tied
into 2nd) plays in one finalist pool, together, regardless of which room
they qualified from.

### Room-phase points carry over

A finalist's room-phase RECESS championship total (§11) is not discarded
and does not reset to zero for the finale. It carries forward as the base
their finale result is added to.

### Finale scoring

The finale Trivia session is scored exactly like a room-phase placement
game (§7, §3): raw scores are recorded, competition ranking is derived, and
that ranking is normalized onto the same 0–20 RECESS scale — but N here is
the number of players in the finalist pool, not a room's roster, since
every qualifier from every room now competes in the same single ranking.

This is a second, independent settlement, not a continuation of any
room-phase game. It produces its own championship-point transactions,
separate from the ones room-phase games already produced.

### Final cumulative total

FINAL_TOTAL =
room-phase RECESS championship total
+ finale Trivia RECESS points

The player with the highest final cumulative total is the RECESS champion.

### What remains unresolved

Exact champion-tie behavior — what happens if two or more finalists share
the single highest FINAL_TOTAL — is intentionally not decided here and must
not be invented by Scoring Engine V1. Every other tie in this document (game
placement, qualification) uses competition ranking with no hidden
tiebreaker; whether the champion tie follows that same pattern, or is
resolved some other way (a tiebreak round, a shared championship, an Admin
call), is a real open decision for RECESS to make separately, not a gap for
the engine to quietly fill in.
