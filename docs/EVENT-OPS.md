# RECESS — Event Operations

This document defines how a RECESS night is actually run.

The software exists to support the night. It should remove arithmetic,
coordination confusion and state-tracking from the humans running it.

The operating principle is:

> Admins and coordinators record facts. RECESS calculates consequences.

---

## 1. Roles

### Admin

The Admin controls the event as a whole.

The Admin can:

- create and configure the event;
- configure the ordered games;
- configure game duration and planned rounds;
- see registrations and check-ins;
- select coordinators;
- create rooms;
- set room capacity;
- monitor every room during the live event;
- approve or reject correction requests;
- directly correct results when necessary;
- pause the event;
- intervene in room progression;
- handle emergency/manual adjustments.

The Admin should not need to manually calculate scores.

---

### Coordinator

Each room must have exactly one active coordinator.

A coordinator is selected by the Admin from people registered for the event
who have not yet checked in.

The coordinator is still a RECESS player and may participate in games.

Their job is intentionally small:

> Get the room ready, start play, keep the room moving and submit what happened.

The coordinator does not calculate RECESS points.

Coordinator permissions are limited to the event and room they are assigned to.

---

### Player

A player:

- registers;
- checks in;
- is assigned to a room;
- follows their room's current state;
- plays the configured games;
- earns RECESS points from their results;
- may qualify for the championship stage.

---

## 2. Rooms

Rooms are created manually by the Admin.

RECESS does not automatically decide how many rooms an event needs.

A room may be created after registration has already opened and may also be
created during check-in when additional capacity is needed.

For RECESS V1, adding a completely new room after the event is already LIVE
should be treated as an Admin recovery action rather than normal flow.

### Room requirements

A room:

- must have an Admin-defined position: Room 01, Room 02, Room 03, etc.;
- must have a capacity between 1 and 15 inclusive;
- cannot be created as an operational room without a coordinator;
- has one coordinator;
- has its own active membership list;
- progresses through the event's games independently of other rooms.

The room capacity includes the coordinator.

### Coordinator seat reservation

Because the coordinator is chosen before they check in, one seat in their room
must be reserved for them.

Example:

Room 02 capacity = 15.

The assigned coordinator has not checked in yet.

The room may therefore contain at most 14 ordinary checked-in players.

When the coordinator checks in, they are assigned directly to Room 02 and take
the reserved fifteenth seat.

The sequential assignment algorithm must never give the coordinator's reserved
seat to another player.

---

## 3. Check-in and room assignment

Room assignment is strict and sequential.

It is NOT random.

Players fill rooms by ascending room position:

Room 01 must fill before ordinary players begin entering Room 02.

Room 02 must fill before ordinary players begin entering Room 03.

And so on.

A player checking in receives the first available non-reserved seat in the
lowest-position room.

Coordinator check-in is the exception: an assigned coordinator goes directly
to their assigned room.

### Waiting for a room

If every currently-created room has no available ordinary-player seat, the
checked-in player becomes:

WAITING_FOR_ROOM

This is not an error.

When the Admin creates another staffed room, waiting players should fill the
newly-available seats in check-in order.

A player must never have more than one active room membership.

---

## 4. Game order

The Admin configures the games for an event in an ordered sequence.

Example:

1. Among Us
2. Skribbl
3. Trivia

Every room follows the same configured order.

A coordinator cannot arbitrarily reorder the games.

Rooms do NOT need to remain perfectly synchronized.

Room 01 may already be preparing Skribbl while Room 03 is finishing its final
Among Us round.

That is allowed.

Each player's application follows the authoritative state of their own room.

---

## 5. Game configuration

Each event game has at least:

- a position in the event;
- a scoring template;
- an Admin-configured duration;
- an Admin-configured planned/max round count;
- game-specific scoring configuration.

The exact duration and number of rounds are event configuration, not hardcoded
RECESS behavior.

### Duration

The duration is the intended game window.

The timer starts when the coordinator starts that game for their room.

When the configured duration expires:

- an active round may be completed;
- a new round should not normally be started;
- the Admin may extend or override the window if necessary.

### Planned rounds

The configured round count is the maximum intended number of scored rounds for
that game.

A game ends for a room when either:

- the configured rounds are completed; or
- the time window expires and the currently-active round has been completed.

Games such as Skribbl or Trivia may normally use one scored session.

Among Us may use several rounds.

---

## 6. Round lifecycle

A scored round has a clear boundary.

Conceptually:

SETUP
→ START
→ PLAYING
→ RESULT ENTRY
→ PREVIEW
→ CONFIRMED
→ COMPLETE

### Participant snapshot

When a coordinator starts a round, RECESS snapshots the players eligible to
participate in that round.

The result may only describe players from that round's participant snapshot.

A player who arrives while a round is already active does not join that active
round.

They become eligible for the next round after the current result is confirmed.

A confirmed result is therefore the authoritative boundary between rounds.

---

## 7. Late arrivals

Late arrivals are allowed.

They receive no retroactive score or points.

If a player joins their room while a round is active:

- they wait;
- they are not included in the active round;
- the coordinator completes and confirms that round;
- the player becomes eligible for the next round.

A missed round is DNP.

---

## 8. DNP and disconnects

DNP means DID NOT PARTICIPATE.

DNP is not a loss.

DNP contributes zero raw score for that round.

A player who disconnects and cannot complete the round is treated as DNP for
that round.

Points already earned in earlier confirmed rounds or games are never removed
because the player later disconnects, leaves or misses another game.

---

## 9. Room communication

Each room has its own human communication layer.

The coordinator is responsible for verbally moving the room through setup,
play, score entry and transitions.

### Voice etiquette

During active gameplay, players should remain muted unless the current game is
in a phase where talking is naturally allowed.

Examples:

Among Us:
- tasks/gameplay → muted;
- meeting/discussion/voting → talking allowed;
- gameplay resumes → muted.

Skribbl:
- active drawing/guessing → muted;
- between rounds → talking may resume.

Trivia:
- active question/answer period → muted;
- between questions or after results → talking may resume.

RECESS does not need to technically control microphones.

This is an event rule enforced socially by the coordinator.

The exact voice-call platform is an event operational choice and is not part of
the scoring engine.

---

## 10. Among Us result entry

For every Among Us round, the coordinator records facts:

- who participated;
- who the actual impostors were;
- which side won;
- who was DNP/disconnected.

The number of impostors is not hardcoded by the scoring engine.

The event/game configuration may allow 1–3 impostors, and the actual roles are
recorded after the round.

The coordinator never types championship points.

RECESS calculates the raw Among Us performance.

---

## 11. Skribbl result entry

Skribbl is played normally using its external room/lobby.

The coordinator distributes the required lobby link.

At the end of the scored session, the coordinator enters the raw scores shown
by Skribbl for the participating players.

Example:

kemz        4210
theo        3980
wh0isalfred 3840

RECESS:

- validates the players;
- sorts the raw scores;
- derives placement;
- shows a preview;
- converts the final game placement into RECESS championship points.

The coordinator never performs the conversion manually.

---

## 12. Trivia result entry

Trivia follows the same placement model as Skribbl.

The external trivia platform produces raw player scores.

The coordinator records those scores.

RECESS derives placement and later converts the completed Trivia game into
RECESS championship points.

---

## 13. Room progression

When a room finishes one game, the coordinator prepares the room for the next
configured game.

Once everybody is ready, the coordinator starts the next game.

This changes the authoritative state of that room.

Players in that room should automatically see the relevant new state.

Example:

AMONG US COMPLETE

becomes:

SKRIBBL — GET READY

then:

SKRIBBL — LIVE

Other rooms may still be on Among Us.

This is expected.

The Admin sees all room states centrally.

---

## 14. Corrections

Before a result is confirmed, the coordinator may freely correct their input.

After confirmation, the result is authoritative.

A coordinator must not silently edit it.

Instead they submit a correction request explaining the incorrect fact and the
replacement.

The Admin may:

- approve the correction;
- reject it;
- or create a direct Admin correction.

An approved correction replaces the source fact/result and causes RECESS to
recalculate every consequence that depends on it.

This may include:

- game raw totals;
- game placement;
- RECESS points;
- room standings;
- qualification.

Point totals themselves are never manually rewritten as the normal correction
mechanism.

---

## 15. Ties

Ties use competition ranking.

Example:

1
2
2
4

Players tied for a position share that position.

RECESS does not secretly break ties.

Qualification-boundary ties are handled by the scoring rules in SCORING.md.

---

## 16. Failures

### Game crash

If an external game crashes before a round is validly completed:

- void the active round;
- award no score from it;
- restart if time allows.

Previously confirmed rounds remain untouched.

### Duplicate submission

Submitting the same result more than once must not duplicate a result or award
points twice.

### Coordinator disappears

The Admin assigns a replacement coordinator.

The room must not lose its existing confirmed results.

### Technical failure

If RECESS itself fails, the night continues.

The room coordinator records:

- who participated;
- roles where applicable;
- raw scores;
- winner/outcome;
- DNPs.

WhatsApp or another agreed backup channel becomes the emergency record.

The Admin backfills the results once RECESS is available again.

The software failing must not end RECESS the event.

---

## 17. Championship stage

Room competition produces the players who qualify for the championship stage.

For RECESS #1, the current intended default is the top 3 positions from each
room.

If a tie touches the qualification boundary, every player tied at that
position qualifies.

The number of qualification positions should remain configurable because the
number of rooms may change.

The exact championship game and final winner mechanism are intentionally not
locked in this document yet.

Room-phase scoring must work independently of that later decision.
