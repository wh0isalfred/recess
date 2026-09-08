# Phase 8 — Manual Phone-Test Checklist

Run this from an actual phone against a real (or staging) Supabase project
with two rooms configured, at least one ROLE_OUTCOME game (Among Us) and
one PLACEMENT game (Skribbl/Trivia) configured on the event, and at least
one registered player assigned as each room's coordinator.

## Entry

- [ ] Log in as an ordinary (non-coordinator) player, go to `/pass`. No
      coordinator banner appears.
- [ ] Manually navigate to `/coordinate` as that same ordinary player. You
      are redirected away — no coordinator controls are ever shown.
- [ ] Log in as a room's actual coordinator. A banner appears on `/pass`
      ("COORDINATING ROOM 0X — GO TO ROOM"). Tapping it opens `/coordinate`.
- [ ] As Room 01's coordinator, note Room 01's real room/round ids, then
      try hitting `/coordinate` while authenticated as Room 02's
      coordinator — you only ever see Room 02's own state, never Room 01's.

## Home screen

- [ ] Room label, occupancy, and roster are correct and match what's
      actually in the room.
- [ ] Before the first game starts: game name and "GET EVERYONE READY"
      show, with a single dominant "START [GAME]" button.
- [ ] After tapping start: the round/game state updates without a manual
      refresh being required.

## Among Us (ROLE_OUTCOME) round

- [ ] Tap "START ROUND 1." The exact current roster is shown as
      participants.
- [ ] While the round is live, have one additional player join the room
      (check in or get reassigned into it). They must NOT appear in this
      round's result-entry list.
- [ ] Mark 1–2 players as impostors, leave the rest as crew (or the
      inverse), mark one player DNP. DNP is visually distinct.
- [ ] Select who won (Crewmates or Impostors).
- [ ] Tap "PREVIEW RESULT." Confirm the preview clearly shows: winning
      side, each participant's role, and the DNP participant marked as
      DNP — before anything is submitted.
- [ ] Tap "CONFIRM." You see "SUBMITTING…" then "RESULT CONFIRMED."
- [ ] Confirm the previously-DNP'd late arrival now appears when you start
      the next round for this same game (next-round eligibility).

## Skribbl/Trivia (PLACEMENT) round

- [ ] Start a round. Every current participant appears with a raw-score
      input.
- [ ] Enter scores for everyone, mark one player DNP (their score input
      disappears/disables).
- [ ] Preview shows raw scores and DNP correctly — no ranking or points
      requested of you, none shown as something you calculated.
- [ ] Confirm succeeds.

## Network failure and retry (launch-critical)

- [ ] Fill out a real result, reach Preview, tap Confirm, and immediately
      switch the phone to Airplane Mode (or kill Wi-Fi) before the request
      completes.
- [ ] You see "NOT SENT — Result was not confirmed," never a false
      "CONFIRMED."
- [ ] Turn the network back on and tap "RETRY." The result confirms
      successfully, and only one result/one set of points exists for that
      round — not two.
- [ ] Repeat, but this time tap Confirm, then rapidly tap it again (or tap
      Retry twice quickly) while online. Only one confirmed result is
      ever created.

## Reload / recovery

- [ ] Mid-round (after starting a round, before confirming a result),
      fully reload the coordinator page (not just re-navigate). You land
      back in result entry for the SAME live round with the SAME
      snapshot — not a blank state, not a duplicate round.
- [ ] Immediately after confirming a round's result, reload the page. You
      see the correct next action (start next round, or finish game),
      not a stale "enter a result" screen for an already-confirmed round.

## Round/game completion

- [ ] Confirm the "FINISH GAME" button is genuinely refused by the
      backend (shows an error, doesn't succeed) if you try it before the
      configured number of rounds is reached and before any configured
      time window has expired.
- [ ] Play through the configured number of rounds for a game. "FINISH
      GAME" now succeeds, and you see the room's standings.
- [ ] From standings, tap "CONTINUE." You land on the next configured
      game's "GET EVERYONE READY" screen — it does NOT auto-start; you
      must explicitly tap "START [NEXT GAME]."

## Timer

- [ ] For a game with a configured duration, a live countdown is visible
      and visibly ticks down in real time.
- [ ] For a game with no configured duration, you see "No time limit
      configured" — never a fabricated number.
- [ ] Reload the page mid-countdown — the timer recomputes to (roughly)
      the same remaining time, not reset to the full duration.

## Corrections

- [ ] After confirming a round's result, look for an ordinary "Edit" — it
      should not exist. Only "Request correction" is offered.
- [ ] Submit a correction request with a reason and a different set of
      facts. You see "PENDING ADMIN REVIEW" — no visible change to the
      room's standings or the confirmed result itself.
- [ ] Confirm there is no way, anywhere in this UI, to approve your own
      correction request.

## Independence across rooms

- [ ] With two coordinators active simultaneously (two phones/two
      sessions), confirm Room 01 progressing through its games has no
      effect on Room 02's own state, timer, or round count, and vice
      versa.

## Visual / usability

- [ ] Every primary action button is comfortably tappable one-handed
      while the phone is held normally during an active game (not a tiny
      target).
- [ ] The screen is legible in a dim/party-lit room (this is the
      aubergine "night" ground, not the cream pre-event look).
- [ ] Nothing on this screen looks like an Admin dashboard — no data
      tables, no dense multi-column layouts.
