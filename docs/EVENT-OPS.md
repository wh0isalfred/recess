# RECESS — Event Operations

How a RECESS night is actually run. This is a human document; the software
exists to serve it.

## Before the night

1. Create the edition and open registration.
2. Create the temporary WhatsApp group and put its link on the event.
3. Confirm each game's room capacity. Among Us caps at 15 per lobby, so the
   number of rooms follows from how many people check in, not from how many
   registered.
4. Assign a coordinator to every room. A room without a coordinator cannot
   submit results.
5. Announce the scoring in the group. People accept a scoring system they
   heard about beforehand and argue with one they discover at 9pm.

## On the night

```
CHECK_IN opens (7:30) -> rooms fill from people who actually showed up
LIVE                  -> game 1, all rooms
                      -> results in from every room
                      -> game 2 ...
COMPLETE              -> standings published
```

### Locked fairness rules

- **Every room completes the same number of scored rounds** for a room-based
  game. A faster Among Us lobby must not farm extra points. Live Control
  warns when room round counts diverge; do not advance until they match.
- **Ties share the position.** Two players tied for 2nd both take 2nd place
  points, 3rd is skipped, the next player is 4th. If a position carries a
  material prize, tied players split it equally. There is no secret
  tiebreaker.
- **DNP is not a loss.** It is zero points for that round and nothing else.
  Points already earned are never removed because someone left early,
  disconnected, or skipped a game.

### Among Us — RECESS #1

- Impostors per round: configurable 1–3, default 3.
- Crewmate win: +2. Impostor win: +4. Loss: 0. DNP: 0.
- The captain ticks who is playing, ticks the impostors, taps who won. That
  is the entire job. The captain never does arithmetic.

Revisit the numbers after the dress rehearsal if Among Us starts dominating
the leaderboard.

## When something breaks

| Situation | What happens |
|---|---|
| Game crashes mid-round | Void the round. No points. Restart it. Confirmed rounds are untouched. |
| Wrong result submitted | Admin edits the source result. RECESS recalculates. Never edit a total. |
| Player disconnects | DNP for that round. Earlier points stand. |
| Player arrives late | They join the next available round. Missed games are DNP. |
| Rooms are full | They wait. Never break an active room to fit someone in. |
| Something technical | PAUSE the event. It is a real state. |

## Emergency mode

**If RECESS the software dies, RECESS the night continues.**

Captains record results in the WhatsApp group — who played, who won, what
placement. Alfred backfills afterwards as MANUAL point transactions.

Tell the coordinators this before the night starts, so nobody freezes waiting
for the app to come back. This is not a coding failure. It is event
operations.

## After

- Publish standings and awards.
- Keep the WhatsApp group a few days for screenshots and banter, then delete
  it. The temporary group is what makes RECESS an event people enter rather
  than another permanent noisy chat.
- Write down what confused players, what coordinators hated, what Alfred did
  by hand, what broke, and what nobody used. That list is the next version.
