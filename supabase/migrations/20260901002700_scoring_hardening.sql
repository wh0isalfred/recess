-- 0027 — Phase 7.1: Scoring Engine hardening.
--
-- Four server-side invariants that 0025 left enforceable only by whatever
-- UI got built on top of it. All four are fixed here, in the functions
-- 0025 defined; migration 0025 itself is untouched.

-- ============================================================ 1+2. start_round

-- Adds two gates before a new round may start, both read fresh from
-- configuration every call — never cached, never hardcoded:
--
--   1. Max rounds (EVENT-OPS.md §5): event_games.planned_rounds is "the
--      maximum intended number of scored rounds." The ceiling counts
--      COMPLETE rounds specifically, not the highest round_index reached —
--      SCORING.md §9 is explicit that a voided round "contributes nothing"
--      and its replacement "is a new valid round," so a void-then-replay
--      must not burn a round the room never actually completed. Gating on
--      round_index instead of a COMPLETE count would do exactly that.
--
--   2. Game window (EVENT-OPS.md §5): once started_at + duration_minutes
--      has passed, a coordinator should not normally start ANOTHER round —
--      but an already-LIVE round is untouched by this (submit_round_result
--      is not gated here at all, so a round in progress when the window
--      closes can still be completed normally). duration_minutes stays
--      nullable (matching rooms.capacity's own "not configured yet is a
--      valid state" precedent from Phase 6.5) — a game with no configured
--      duration has no enforceable window, not a blocked one; making
--      duration mandatory here would silently block every coordinator
--      until an Admin happens to set a number for something EVENT-OPS.md
--      itself never states must be pre-set before play can begin. Admin
--      extension is exactly admin_update_event_game() (already built) —
--      raising duration_minutes for this event_game re-opens the window on
--      the very next call, since this reads the live value, not a copy.
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
  v_event_game record;
  v_completed_count integer;
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

  select * into v_event_game from event_games where id = p_event_game_id;

  select count(*) into v_completed_count from rounds
   where room_id = p_room_id and event_game_id = p_event_game_id and status = 'COMPLETE';
  if v_completed_count >= v_event_game.planned_rounds then
    raise exception 'rounds_exhausted: this room has already completed the configured maximum of % round(s) for this game', v_event_game.planned_rounds
      using errcode = '55000';
  end if;

  if v_event_game.duration_minutes is not null
     and v_room_event_game.started_at is not null
     and now() > v_room_event_game.started_at + (v_event_game.duration_minutes || ' minutes')::interval
  then
    raise exception 'game_window_expired: this room''s configured game window has ended — an Admin can extend it by updating this game''s duration'
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

-- ============================================================ 3. validate_round_payload

-- Same shape and signature as 0025's version, with one addition: instead
-- of comparing only array LENGTH against the snapshot count (which a
-- payload with one duplicate and one omission can satisfy while
-- representing entirely the wrong set of participants), this now compares
-- the actual SORTED SET of registration_ids named in the payload against
-- the sorted set in the snapshot. Sorted-array equality catches a
-- duplicate, a missing snapshot member, an extra/unknown id, or any
-- combination, in one check — two arrays of equal length can still differ
-- once sorted if their multisets of values differ, which is exactly what a
-- duplicate-for-a-missing swap produces.
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
  v_entry jsonb;
  v_reg_id uuid;
  v_participation public.participation_state;
  v_role text;
  v_raw_score numeric;
  v_winning_role text;
  v_roles jsonb;
  v_payload_ids uuid[] := '{}';
  v_snapshot_ids uuid[];
begin
  select r.*, eg.scoring_template, eg.scoring_config
    into v_round
    from rounds r join event_games eg on eg.id = r.event_game_id
   where r.id = p_round_id;
  if not found then
    raise exception 'round_not_found: no such round' using errcode = 'no_data_found';
  end if;

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

    for v_entry in select * from jsonb_array_elements(p_payload->'participants') loop
      v_reg_id := (v_entry->>'registrationId')::uuid;
      if v_reg_id is null then
        raise exception 'invalid_payload: participant entry missing registrationId' using errcode = '22023';
      end if;
      if not exists (select 1 from round_participants where round_id = p_round_id and round_participants.registration_id = v_reg_id) then
        raise exception 'invalid_participant: % is not in this round''s participant snapshot', v_reg_id
          using errcode = '22023';
      end if;
      v_payload_ids := v_payload_ids || v_reg_id;

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

    for v_entry in select * from jsonb_array_elements(p_payload->'scores') loop
      v_reg_id := (v_entry->>'registrationId')::uuid;
      if v_reg_id is null then
        raise exception 'invalid_payload: score entry missing registrationId' using errcode = '22023';
      end if;
      if not exists (select 1 from round_participants where round_id = p_round_id and round_participants.registration_id = v_reg_id) then
        raise exception 'invalid_participant: % is not in this round''s participant snapshot', v_reg_id
          using errcode = '22023';
      end if;
      v_payload_ids := v_payload_ids || v_reg_id;

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

  select coalesce(array_agg(rp.registration_id order by rp.registration_id), '{}')
    into v_snapshot_ids
    from round_participants rp where rp.round_id = p_round_id;

  if (select array_agg(x order by x) from unnest(v_payload_ids) x) is distinct from v_snapshot_ids then
    raise exception 'payload_participant_mismatch: the payload must name exactly the round''s snapshot participants, each exactly once (no duplicates, none missing, none extra)'
      using errcode = '22023';
  end if;
end;
$$;

-- ============================================================ 4. submit_round_result

-- Same as 0025's version, with one change: an idempotency key that
-- already exists is only treated as a safe retry if it belongs to THIS
-- round. A key already bound to a different round is a real error, not a
-- silent hand-off to that other round's result — the caller is already
-- known to be authorized for p_round_id's room by this point (the
-- authorization check above still runs first, unchanged), but that does
-- not make them authorized for whatever OTHER round a reused key happens
-- to reference, and this function must not disclose that round's result
-- id to them regardless.
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

  -- Idempotency: the same key returns the same outcome ONLY for the round
  -- it actually belongs to. A double-tap on the round the caller is
  -- authorized for and actually submitting to is safe; a key that turns
  -- out to name a different round is rejected outright, not resolved by
  -- quietly handing back that other round's result.
  select * into v_existing_by_key from results where idempotency_key = p_idempotency_key;
  if found then
    if v_existing_by_key.round_id <> p_round_id then
      raise exception 'idempotency_key_reused: this idempotency key already belongs to a different round'
        using errcode = '22023';
    end if;
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
