-- 0025 — Phase 7: Scoring Engine V1.
--
-- Builds on schema that already existed, unused, from Gate A (rounds,
-- round_participants, results, point_transactions — 0008/0009) and on
-- room_event_games (0021, Phase 6.5). Nothing here redesigns those tables;
-- two nullable columns are added where the existing shape genuinely had no
-- place for something this phase needs (see below), and everything else is
-- new functions.
--
-- The three-layer separation (SCORING.md §2) maps onto existing objects
-- exactly:
--   RAW GAME PERFORMANCE  → results.payload (per round, immutable, append-
--                           only via supersession — already built)
--   GAME PLACEMENT        → computed at settlement, not stored
--   RECESS CHAMPIONSHIP
--   POINTS                → point_transactions (already built: the ledger)
--
-- Round-level submission (submit_round_result) records facts only — no
-- point_transactions are written per round. A room-game is SETTLED (raw
-- totals aggregated, ranked, normalized to 0-20, ledger written) exactly
-- once, when the coordinator completes that game — extending
-- complete_room_game() (0021) is literally where SCORING.md §10 says
-- settlement happens ("the room-game is settled when the coordinator
-- completes that game"), not a separate action this schema would otherwise
-- need to invent a trigger for.

-- ============================================================ 1. COLUMNS

-- round_participants needs somewhere to record what actually happened,
-- distinct from who was merely snapshotted as eligible. participation and
-- role_key already exist and are mutable (no update-guard trigger, unlike
-- results/point_transactions) — exactly the shape a snapshot-then-record
-- table should have. raw_score is the one genuinely missing piece: a
-- PLACEMENT round's per-participant external-platform score has nowhere
-- to live. ROLE_OUTCOME doesn't need it — role_key plus the round's own
-- winning_role (in results.payload) is enough to derive raw points at
-- settlement time.
alter table public.round_participants add column raw_score numeric;

comment on column public.round_participants.raw_score is
  'PLACEMENT games only: the external platform''s raw score for this
   participant in this round, recorded when the round''s result is
   confirmed. Null for ROLE_OUTCOME (role_key + the round''s winning_role
   already determine raw points) and for anyone still DNP.';

-- point_transactions needs a stable, unambiguous way to identify "every
-- transaction produced by this room's settlement of this game" — robust
-- across corrections to ANY round in that game, not just the one whose
-- confirmation happened to complete it. result_id/round_id alone can't do
-- this: a correction to an earlier round changes nothing about which round
-- originally completed the game, yet must still trigger re-settlement of
-- the same transactions. room_event_games (0021) is already exactly "this
-- room's row for this game" — the natural, existing grouping key.
alter table public.point_transactions
  add column room_event_game_id uuid references public.room_event_games (id) on delete restrict;

comment on column public.point_transactions.room_event_game_id is
  'Set for RESULT-sourced settlement transactions only — identifies which
   room''s settlement of which game produced this row, so a correction to
   any round of that game can find and void every transaction the PREVIOUS
   settlement produced before writing the replacement set. Null for
   MANUAL_ADJUSTMENT rows, which are not tied to a room-game at all.';

-- superseded_by's FK needs to be checked at end-of-transaction, not
-- end-of-statement: correcting a round means updating the OLD result's
-- superseded_by to point at a NEW result row that is inserted in the very
-- next statement of the same transaction. A same-statement-checked FK can
-- never see that new row in time — it doesn't exist yet when the UPDATE
-- runs. This changes only when the constraint is checked, not what it
-- checks; same columns, same reference, same ON DELETE SET NULL.
alter table public.results drop constraint results_superseded_by_fkey;
alter table public.results add constraint results_superseded_by_fkey
  foreign key (superseded_by) references public.results (id) on delete set null
  deferrable initially deferred;

-- ============================================================ 2. start_round

-- Snapshots eligible participants at the moment the round starts — anyone
-- with an active room_membership in this room right now. A player who
-- joins the room later is simply not in this snapshot; they become
-- eligible starting with the NEXT call to start_round (EVENT-OPS.md §7).
create or replace function public.start_round(
  p_room_id uuid,
  p_event_game_id uuid
) returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_event_id uuid;
  v_room_event_game record;
  v_next_index integer;
  v_round public.rounds;
  v_participant_count integer;
begin
  select event_id into v_event_id from rooms where id = p_room_id;
  if v_event_id is null then
    raise exception 'room_not_found: no such room' using errcode = 'no_data_found';
  end if;

  if not public.is_authorized_for_room(p_room_id) then
    raise exception 'not_authorized: not this room''s coordinator or an event admin' using errcode = '42501';
  end if;

  select * into v_room_event_game from room_event_games
   where room_id = p_room_id and event_game_id = p_event_game_id for update;
  if not found or v_room_event_game.status <> 'LIVE' then
    raise exception 'room_game_not_live: start_room_game() must be called for this room before starting a round'
      using errcode = '55000';
  end if;

  if exists (
    select 1 from rounds
     where room_id = p_room_id and event_game_id = p_event_game_id and status = 'LIVE'
  ) then
    raise exception 'round_already_live: this room already has a live round for this game' using errcode = '55000';
  end if;

  select coalesce(max(round_index), 0) + 1 into v_next_index
    from rounds where room_id = p_room_id and event_game_id = p_event_game_id;

  insert into rounds (event_id, event_game_id, room_id, round_index, status, started_at)
  values (v_event_id, p_event_game_id, p_room_id, v_next_index, 'LIVE', now())
  returning * into v_round;

  insert into round_participants (event_id, round_id, registration_id, participation)
  select v_event_id, v_round.id, rm.registration_id, 'PARTICIPATING'
    from room_memberships rm
   where rm.room_id = p_room_id and rm.left_at is null;

  get diagnostics v_participant_count = row_count;

  insert into audit_logs (event_id, actor_user_id, action, entity_type, entity_id, after)
  values (v_event_id, auth.uid(), 'round.started', 'rounds', v_round.id,
          jsonb_build_object('roomId', p_room_id, 'eventGameId', p_event_game_id,
                              'roundIndex', v_round.round_index, 'participantCount', v_participant_count));

  return jsonb_build_object(
    'roundId', v_round.id, 'roundIndex', v_round.round_index, 'participantCount', v_participant_count,
    'participants', (
      select coalesce(jsonb_agg(jsonb_build_object('registrationId', er.id, 'alias', er.alias)), '[]'::jsonb)
        from round_participants rp
        join event_registrations er on er.id = rp.registration_id
       where rp.round_id = v_round.id
    )
  );
end;
$$;

revoke all on function public.start_round(uuid, uuid) from public;
grant execute on function public.start_round(uuid, uuid) to authenticated;

-- ================================================== shared payload validator

-- Used by both preview_round_result (read-only) and submit_round_result
-- (writes). Returns one row per snapshot participant with the facts the
-- payload assigned them, or raises on anything invalid — an unknown
-- registration, a role outside the event-game's configured composition,
-- a participant missing from the payload entirely, or a DNP participant
-- carrying a role/score. Never mutates anything; callers decide whether to
-- write the result.
create or replace function public.validate_round_payload(
  p_round_id uuid,
  p_payload jsonb
) returns table (registration_id uuid, participation public.participation_state, role_key text, raw_score numeric)
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
declare
  v_round record;
  v_event_game record;
  v_snapshot_count integer;
  v_payload_count integer;
  v_entry jsonb;
  v_reg_id uuid;
  v_participation public.participation_state;
  v_role text;
  v_raw_score numeric;
  v_winning_role text;
  v_roles jsonb;
begin
  select r.*, eg.scoring_template, eg.scoring_config
    into v_round
    from rounds r join event_games eg on eg.id = r.event_game_id
   where r.id = p_round_id;
  if not found then
    raise exception 'round_not_found: no such round' using errcode = 'no_data_found';
  end if;

  select count(*) into v_snapshot_count from round_participants where round_id = p_round_id;

  if v_round.scoring_template = 'ROLE_OUTCOME' then
    v_winning_role := p_payload->>'winningRole';
    if v_winning_role is null or btrim(v_winning_role) = '' then
      raise exception 'invalid_payload: winningRole is required' using errcode = '22023';
    end if;
    v_roles := coalesce(v_round.scoring_config->'awards', '{}'::jsonb);
    if not (v_roles ? v_winning_role) then
      raise exception 'invalid_payload: winningRole % is not a configured role for this game', v_winning_role
        using errcode = '22023';
    end if;

    if jsonb_typeof(p_payload->'participants') <> 'array' then
      raise exception 'invalid_payload: participants must be an array' using errcode = '22023';
    end if;
    v_payload_count := jsonb_array_length(p_payload->'participants');

    for v_entry in select * from jsonb_array_elements(p_payload->'participants') loop
      v_reg_id := (v_entry->>'registrationId')::uuid;
      if v_reg_id is null then
        raise exception 'invalid_payload: participant entry missing registrationId' using errcode = '22023';
      end if;
      if not exists (select 1 from round_participants where round_id = p_round_id and round_participants.registration_id = v_reg_id) then
        raise exception 'invalid_participant: % is not in this round''s participant snapshot', v_reg_id
          using errcode = '22023';
      end if;

      v_participation := coalesce(v_entry->>'participation', 'PARTICIPATING')::public.participation_state;
      v_role := v_entry->>'role';

      if v_participation = 'DNP' then
        if v_role is not null then
          raise exception 'invalid_payload: a DNP participant cannot carry a role' using errcode = '22023';
        end if;
      else
        if v_role is null or not (v_roles ? v_role) then
          raise exception 'invalid_payload: % is not a configured role for this game', coalesce(v_role, 'null')
            using errcode = '22023';
        end if;
      end if;

      registration_id := v_reg_id;
      participation := v_participation;
      role_key := v_role;
      raw_score := null;
      return next;
    end loop;

  elsif v_round.scoring_template = 'PLACEMENT' then
    if jsonb_typeof(p_payload->'scores') <> 'array' then
      raise exception 'invalid_payload: scores must be an array' using errcode = '22023';
    end if;
    v_payload_count := jsonb_array_length(p_payload->'scores');

    for v_entry in select * from jsonb_array_elements(p_payload->'scores') loop
      v_reg_id := (v_entry->>'registrationId')::uuid;
      if v_reg_id is null then
        raise exception 'invalid_payload: score entry missing registrationId' using errcode = '22023';
      end if;
      if not exists (select 1 from round_participants where round_id = p_round_id and round_participants.registration_id = v_reg_id) then
        raise exception 'invalid_participant: % is not in this round''s participant snapshot', v_reg_id
          using errcode = '22023';
      end if;

      v_participation := coalesce(v_entry->>'participation', 'PARTICIPATING')::public.participation_state;

      if v_participation = 'DNP' then
        if v_entry ? 'rawScore' then
          raise exception 'invalid_payload: a DNP participant cannot carry a raw score' using errcode = '22023';
        end if;
        v_raw_score := null;
      else
        if not (v_entry ? 'rawScore') then
          raise exception 'invalid_payload: participant % is missing rawScore', v_reg_id using errcode = '22023';
        end if;
        v_raw_score := (v_entry->>'rawScore')::numeric;
        if v_raw_score < 0 then
          raise exception 'invalid_payload: rawScore cannot be negative' using errcode = '22023';
        end if;
      end if;

      registration_id := v_reg_id;
      participation := v_participation;
      role_key := null;
      raw_score := v_raw_score;
      return next;
    end loop;

  else
    raise exception 'unsupported_template: % scoring is not implemented in this phase', v_round.scoring_template
      using errcode = '55000';
  end if;

  if v_payload_count <> v_snapshot_count then
    raise exception 'incomplete_payload: expected % participants from the round snapshot, got %', v_snapshot_count, v_payload_count
      using errcode = '22023';
  end if;
end;
$$;

revoke all on function public.validate_round_payload(uuid, jsonb) from public;

-- ============================================================ preview_round_result

-- Read-only. Same validation submit_round_result uses, no writes at all —
-- "preview must not mutate authoritative scoring state."
create or replace function public.preview_round_result(
  p_round_id uuid,
  p_payload jsonb
) returns jsonb
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
declare
  v_room_id uuid;
begin
  select room_id into v_room_id from rounds where id = p_round_id;
  if v_room_id is null then
    raise exception 'round_not_found: no such round' using errcode = 'no_data_found';
  end if;
  if not public.is_authorized_for_room(v_room_id) then
    raise exception 'not_authorized: not this room''s coordinator or an event admin' using errcode = '42501';
  end if;

  return jsonb_build_object(
    'roundId', p_round_id,
    'facts', (
      select coalesce(jsonb_agg(jsonb_build_object(
               'registrationId', v.registration_id, 'alias', er.alias,
               'participation', v.participation, 'role', v.role_key, 'rawScore', v.raw_score
             )), '[]'::jsonb)
        from public.validate_round_payload(p_round_id, p_payload) v
        join event_registrations er on er.id = v.registration_id
    )
  );
end;
$$;

revoke all on function public.preview_round_result(uuid, jsonb) from public;
grant execute on function public.preview_round_result(uuid, jsonb) to authenticated;

-- ============================================================ submit_round_result

-- The real writer. Idempotent (a repeated idempotency_key returns the
-- existing outcome, never a duplicate), and a correction (same round, new
-- payload, new idempotency_key) is the exact same function, not a
-- different code path — supersession plus, if the room-game was already
-- settled, immediate re-settlement.
create or replace function public.submit_round_result(
  p_round_id uuid,
  p_payload jsonb,
  p_idempotency_key text
) returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_uid uuid := auth.uid();
  v_round record;
  v_existing_result record;
  v_existing_by_key record;
  v_new_result public.results;
  v_new_result_id uuid := gen_random_uuid();
  v_room_event_game record;
begin
  if p_idempotency_key is null or length(p_idempotency_key) < 8 then
    raise exception 'invalid_idempotency_key: a real client-generated key is required' using errcode = '22023';
  end if;

  select r.*, eg.scoring_template as event_game_scoring_template into v_round
    from rounds r join event_games eg on eg.id = r.event_game_id
   where r.id = p_round_id for update of r;
  if not found then
    raise exception 'round_not_found: no such round' using errcode = 'no_data_found';
  end if;
  if not public.is_authorized_for_room(v_round.room_id) then
    raise exception 'not_authorized: not this room''s coordinator or an event admin' using errcode = '42501';
  end if;
  if v_round.status = 'VOID' then
    raise exception 'round_voided: a voided round cannot receive a result' using errcode = '55000';
  end if;

  -- Idempotency: the same key always returns the same outcome, regardless
  -- of which round the caller thinks it belongs to — a double-tap is safe
  -- even across a network retry that somehow raced a round transition.
  select * into v_existing_by_key from results where idempotency_key = p_idempotency_key;
  if found then
    return jsonb_build_object('roundId', v_existing_by_key.round_id, 'resultId', v_existing_by_key.id, 'idempotent', true);
  end if;

  -- Validate first — nothing is written if the payload is bad.
  perform 1 from public.validate_round_payload(p_round_id, p_payload) limit 1;

  select * into v_existing_result from results
   where round_id = p_round_id and superseded_at is null for update;

  if v_existing_result.id is not null then
    update results set superseded_at = now(), superseded_by = v_new_result_id where id = v_existing_result.id;
  end if;

  insert into results (id, event_id, round_id, template, payload, idempotency_key, submitted_by)
  values (v_new_result_id, v_round.event_id, p_round_id, v_round.event_game_scoring_template, p_payload, p_idempotency_key, v_uid)
  returning * into v_new_result;

  update round_participants rp
     set participation = v.participation, role_key = v.role_key, raw_score = v.raw_score
    from public.validate_round_payload(p_round_id, p_payload) v
   where rp.round_id = p_round_id and rp.registration_id = v.registration_id;

  update rounds set status = 'COMPLETE', ended_at = coalesce(ended_at, now()) where id = p_round_id;

  insert into audit_logs (event_id, actor_user_id, action, entity_type, entity_id, before, after)
  values (v_round.event_id, v_uid, case when v_existing_result.id is not null then 'result.corrected' else 'result.submitted' end,
          'results', v_new_result.id,
          case when v_existing_result.id is not null then jsonb_build_object('previousResultId', v_existing_result.id) else null end,
          jsonb_build_object('roundId', p_round_id, 'payload', p_payload));

  -- A correction to a round belonging to an already-settled room-game must
  -- re-settle immediately — SCORING.md §13, steps 3-9 — not wait for some
  -- later action that may never come.
  select * into v_room_event_game
    from room_event_games where room_id = v_round.room_id and event_game_id = v_round.event_game_id;
  if found and v_room_event_game.status = 'COMPLETE' then
    perform public.settle_room_game_now(v_round.room_id, v_round.event_game_id);
  end if;

  return jsonb_build_object('roundId', p_round_id, 'resultId', v_new_result.id, 'idempotent', false,
                             'corrected', v_existing_result.id is not null);
end;
$$;

revoke all on function public.submit_round_result(uuid, jsonb, text) from public;
grant execute on function public.submit_round_result(uuid, jsonb, text) to authenticated;

-- ============================================================ void_round

-- A round that crashed before ever being validly completed — EVENT-OPS.md
-- §16. Only a LIVE round can be voided (a COMPLETE round's fix path is
-- correction via submit_round_result, not voiding; a DRAFT round was never
-- started; an already-VOID round is simply already handled).
create or replace function public.void_round(
  p_round_id uuid,
  p_reason text
) returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_uid uuid := auth.uid();
  v_round record;
begin
  select * into v_round from rounds where id = p_round_id for update;
  if not found then
    raise exception 'round_not_found: no such round' using errcode = 'no_data_found';
  end if;
  if not public.is_authorized_for_room(v_round.room_id) then
    raise exception 'not_authorized: not this room''s coordinator or an event admin' using errcode = '42501';
  end if;
  if v_round.status <> 'LIVE' then
    raise exception 'round_not_live: only a live round can be voided' using errcode = '55000';
  end if;
  if btrim(coalesce(p_reason, '')) = '' then
    raise exception 'invalid_reason: a reason is required to void a round' using errcode = '22023';
  end if;

  update rounds set status = 'VOID', ended_at = now() where id = p_round_id;

  insert into audit_logs (event_id, actor_user_id, action, entity_type, entity_id, after)
  values (v_round.event_id, v_uid, 'round.voided', 'rounds', p_round_id, jsonb_build_object('reason', p_reason));

  return jsonb_build_object('roundId', p_round_id, 'status', 'VOID');
end;
$$;

revoke all on function public.void_round(uuid, text) from public;
grant execute on function public.void_round(uuid, text) to authenticated;

-- ============================================================ settle_room_game_now

-- Internal (not granted to authenticated — called only from
-- complete_room_game and from submit_round_result's re-settlement path).
-- Aggregates every confirmed (non-superseded, from a non-void round)
-- result for this room+game, ranks the totals with competition ranking,
-- normalizes onto 0-20, and replaces the room-game's current settlement
-- transactions atomically: void the old set (if any), insert the new one.
-- A player with zero raw performance across every round (full-game DNP)
-- never enters the ranked set at all — SCORING.md §4, §8.
create or replace function public.settle_room_game_now(
  p_room_id uuid,
  p_event_game_id uuid
) returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_room_event_game record;
  v_event_game record;
  v_last_round_id uuid;
  v_settled_count integer := 0;
begin
  select * into v_room_event_game from room_event_games
   where room_id = p_room_id and event_game_id = p_event_game_id for update;
  if not found then
    raise exception 'room_game_not_found: this room has not started this game' using errcode = 'no_data_found';
  end if;

  select * into v_event_game from event_games where id = p_event_game_id;

  select r.id into v_last_round_id
    from rounds r
   where r.room_id = p_room_id and r.event_game_id = p_event_game_id and r.status = 'COMPLETE'
   order by r.round_index desc limit 1;

  -- Void the previous settlement's transactions in full, whatever produced
  -- them — this function is idempotent-safe to call repeatedly and is
  -- exactly what a correction needs: old points gone, new points in,
  -- inside the same transaction as everything else here.
  update point_transactions
     set voided_at = now(), voided_by = auth.uid()
   where room_event_game_id = v_room_event_game.id and source = 'RESULT' and voided_at is null;

  -- Raw totals per player, from every confirmed round of this room+game.
  create temporary table if not exists tmp_settlement_totals (registration_id uuid primary key, raw_total numeric) on commit drop;
  delete from tmp_settlement_totals;

  if v_event_game.scoring_template = 'PLACEMENT' then
    insert into tmp_settlement_totals (registration_id, raw_total)
    select rp.registration_id, sum(rp.raw_score)
      from round_participants rp
      join rounds r on r.id = rp.round_id
     where r.room_id = p_room_id and r.event_game_id = p_event_game_id and r.status = 'COMPLETE'
       and rp.participation = 'PARTICIPATING'
     group by rp.registration_id;

  elsif v_event_game.scoring_template = 'ROLE_OUTCOME' then
    insert into tmp_settlement_totals (registration_id, raw_total)
    select rp.registration_id, sum(
             case
               when res.payload->>'winningRole' = rp.role_key
                 then coalesce((v_event_game.scoring_config->'awards'->rp.role_key->>'win')::numeric, 0)
               else coalesce((v_event_game.scoring_config->'awards'->rp.role_key->>'loss')::numeric, 0)
             end
           )
      from round_participants rp
      join rounds r on r.id = rp.round_id
      join results res on res.round_id = r.id and res.superseded_at is null
     where r.room_id = p_room_id and r.event_game_id = p_event_game_id and r.status = 'COMPLETE'
       and rp.participation = 'PARTICIPATING'
     group by rp.registration_id;
  else
    raise exception 'unsupported_template: % settlement is not implemented in this phase', v_event_game.scoring_template
      using errcode = '55000';
  end if;

  -- Competition ranking (1, 2, 2, 4 — SCORING.md §5) and normalization.
  -- N is the ranked player count; for N=1 the sole participant simply
  -- takes the maximum (the formula's own denominator is undefined at
  -- N=1, and a field of one has no meaningful spread to normalize across).
  with ranked as (
    select registration_id, raw_total,
           rank() over (order by raw_total desc) as placement,
           count(*) over () as n
      from tmp_settlement_totals
  )
  insert into point_transactions (event_id, registration_id, points, source, result_id, round_id, event_game_id, room_event_game_id, created_by)
  select v_room_event_game.event_id, registration_id,
         case when n <= 1 then 20 else round(20.0 * (n - placement) / (n - 1))::integer end,
         'RESULT', (select id from results where round_id = v_last_round_id and superseded_at is null),
         v_last_round_id, p_event_game_id, v_room_event_game.id, auth.uid()
    from ranked;

  get diagnostics v_settled_count = row_count;

  insert into audit_logs (event_id, actor_user_id, action, entity_type, entity_id, after)
  values (v_room_event_game.event_id, auth.uid(), 'room_game.settled', 'room_event_games', v_room_event_game.id,
          jsonb_build_object('roomId', p_room_id, 'eventGameId', p_event_game_id, 'rankedPlayers', v_settled_count));

  return jsonb_build_object('roomId', p_room_id, 'eventGameId', p_event_game_id, 'rankedPlayers', v_settled_count);
end;
$$;

revoke all on function public.settle_room_game_now(uuid, uuid) from public;

-- ============================================================ complete_room_game

-- Extends 0021's version additively: refuses completion while any round
-- for this room+game is still LIVE, and triggers settlement as its very
-- last step, exactly where SCORING.md §10 places it. Everything 0021 did
-- (authorization, idempotent already-COMPLETE handling, the not-LIVE
-- rejection) is unchanged.
create or replace function public.complete_room_game(
  p_room_id uuid,
  p_event_game_id uuid
) returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_row public.room_event_games;
begin
  if not public.is_authorized_for_room(p_room_id) then
    raise exception 'not_authorized: not this room''s coordinator or an event admin' using errcode = '42501';
  end if;

  select * into v_row from room_event_games
   where room_id = p_room_id and event_game_id = p_event_game_id for update;

  if not found then
    raise exception 'room_game_not_found: this room has not started this game' using errcode = 'no_data_found';
  end if;

  if v_row.status = 'COMPLETE' then
    return jsonb_build_object('roomId', p_room_id, 'eventGameId', p_event_game_id, 'status', v_row.status);
  end if;
  if v_row.status <> 'LIVE' then
    raise exception 'room_game_not_live: this room''s game is not currently live' using errcode = '55000';
  end if;

  if exists (
    select 1 from rounds
     where room_id = p_room_id and event_game_id = p_event_game_id and status = 'LIVE'
  ) then
    raise exception 'round_still_live: a round for this room and game is still live — complete or void it first'
      using errcode = '55000';
  end if;

  update room_event_games
     set status = 'COMPLETE', ended_at = now()
   where id = v_row.id
   returning * into v_row;

  perform public.settle_room_game_now(p_room_id, p_event_game_id);

  return jsonb_build_object('roomId', p_room_id, 'eventGameId', p_event_game_id, 'status', v_row.status, 'endedAt', v_row.ended_at);
end;
$$;

-- ============================================================ room_standings

-- Derived entirely from the ledger — "do not directly mutate a player's
-- championship total as stored truth." Qualification (positions 1-2, ties
-- at the boundary all qualify) is computed here rather than stored, for
-- the same reason: it is a pure function of the current standings, never
-- an independent fact that could drift from them.
create or replace function public.room_standings(p_room_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
declare
  v_event_id uuid;
  v_qualify_count integer := 2;
begin
  select event_id into v_event_id from rooms where id = p_room_id;
  if v_event_id is null then
    raise exception 'room_not_found: no such room' using errcode = 'no_data_found';
  end if;
  perform public.require_event_admin();

  return coalesce((
    with totals as (
      select rm.registration_id, coalesce(sum(pt.points), 0) as total_points
        from room_memberships rm
        left join point_transactions pt
          on pt.registration_id = rm.registration_id and pt.voided_at is null
        and pt.event_id = v_event_id
       where rm.room_id = p_room_id and rm.left_at is null
       group by rm.registration_id
    ),
    ranked as (
      select er.id, er.alias, t.total_points,
             rank() over (order by t.total_points desc) as placement
        from totals t
        join event_registrations er on er.id = t.registration_id
    )
    select jsonb_agg(jsonb_build_object(
             'registrationId', id, 'alias', alias, 'totalPoints', total_points,
             'placement', placement, 'qualifies', placement <= v_qualify_count
           ) order by placement, alias)
      from ranked
  ), '[]'::jsonb);
end;
$$;

revoke all on function public.room_standings(uuid) from public;
grant execute on function public.room_standings(uuid) to authenticated;

-- ============================================================ admin_manual_adjustment

-- The emergency escape hatch — SCORING.md §16. Admin-only, requires a
-- real reason, always visible in the same audit history as everything
-- else. Not tied to a room_event_game (a manual adjustment may have
-- nothing to do with any single game), so room_event_game_id stays null.
create or replace function public.admin_manual_adjustment(
  p_event_slug text,
  p_registration_id uuid,
  p_points integer,
  p_note text
) returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_uid uuid := auth.uid();
  v_event_id uuid;
  v_txn public.point_transactions;
begin
  perform public.require_event_admin();

  select id into v_event_id from events where slug = p_event_slug;
  if not found then
    raise exception 'event_not_found: no such event' using errcode = 'no_data_found';
  end if;

  if not exists (select 1 from event_registrations where id = p_registration_id and event_id = v_event_id) then
    raise exception 'registration_not_found: no such registration on this event' using errcode = 'no_data_found';
  end if;

  if btrim(coalesce(p_note, '')) = '' then
    raise exception 'invalid_note: a reason is required for a manual adjustment' using errcode = '22023';
  end if;

  insert into point_transactions (event_id, registration_id, points, source, note, created_by)
  values (v_event_id, p_registration_id, p_points, 'MANUAL_ADJUSTMENT', p_note, v_uid)
  returning * into v_txn;

  insert into audit_logs (event_id, actor_user_id, action, entity_type, entity_id, after)
  values (v_event_id, v_uid, 'points.manual_adjustment', 'point_transactions', v_txn.id,
          jsonb_build_object('registrationId', p_registration_id, 'points', p_points, 'note', p_note));

  return jsonb_build_object('id', v_txn.id, 'points', v_txn.points);
end;
$$;

revoke all on function public.admin_manual_adjustment(text, uuid, integer, text) from public;
grant execute on function public.admin_manual_adjustment(text, uuid, integer, text) to authenticated;
