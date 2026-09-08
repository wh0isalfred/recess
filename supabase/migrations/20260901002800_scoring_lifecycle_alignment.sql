-- 0028 — Phase 7.2: scoring lifecycle alignment.
--
-- Two fixes, both to functions defined in 0025/0027 (superseded here via
-- create or replace; neither migration file is touched):
--
--   1. A confirmed result can no longer be corrected in place by whoever
--      happens to be the room's coordinator. EVENT-OPS.md §14: after
--      confirmation the coordinator "must not silently edit it" — they
--      "submit a correction request explaining the incorrect fact and the
--      replacement," and only Admin approval "replaces the source
--      fact/result." submit_round_result() (0025/0027) let an authorized
--      coordinator supersede a confirmed result immediately, which is
--      exactly the shortcut this document rules out.
--
--   2. complete_room_game() let a coordinator end a game the moment no
--      round was LIVE, with no check that the configured round count or
--      time window had actually been reached — an arbitrary early finish
--      EVENT-OPS.md never describes as normal.

-- ============================================================ 0. validate_round_payload (bugfix)

-- Fixes a real latent bug in 0027's version, found while testing this
-- migration: when a round's participant snapshot is genuinely empty (a
-- room with a coordinator but no ordinary members yet, for instance),
-- unnest() over an empty payload-ids array produces zero rows, and
-- array_agg() over zero rows returns NULL — not an empty array. The
-- snapshot side already normalized this correctly via coalesce(...,
-- '{}'), but the payload side did not, so NULL was compared against '{}'
-- and treated as a mismatch even though both sides genuinely named zero
-- participants. Wrapping the payload side in the same coalesce fixes it.
-- No other line of 0027's version is changed.
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

  if coalesce((select array_agg(x order by x) from unnest(v_payload_ids) x), '{}') is distinct from v_snapshot_ids then
    raise exception 'payload_participant_mismatch: the payload must name exactly the round''s snapshot participants, each exactly once (no duplicates, none missing, none extra)'
      using errcode = '22023';
  end if;
end;
$$;

-- ============================================================ 1. ENUM + TABLE

create type public.correction_request_status as enum ('PENDING', 'APPROVED', 'REJECTED');

create table public.correction_requests (
  id                   uuid primary key default gen_random_uuid(),
  -- Denormalised event_id/room_id, same reasoning room_coordinators/
  -- room_event_games already use: makes it structurally impossible for a
  -- request to reference a round from a different event or room than it
  -- claims, and gives the append-only guard below something cheap to
  -- re-verify without extra joins.
  event_id             uuid not null references public.events (id) on delete cascade,
  room_id              uuid not null,
  round_id             uuid not null,
  current_result_id    uuid not null references public.results (id) on delete restrict,
  requested_by         uuid not null,
  reason               text not null,
  proposed_payload     jsonb not null,
  status               public.correction_request_status not null default 'PENDING',
  decided_by           uuid,
  decided_at           timestamptz,
  decision_note        text,
  created_at           timestamptz not null default now(),

  constraint correction_requests_reason_not_blank check (btrim(reason) <> ''),
  constraint correction_requests_decision_pair check (
    (status = 'PENDING' and decided_by is null and decided_at is null)
    or (status <> 'PENDING' and decided_by is not null and decided_at is not null)
  ),
  constraint correction_requests_round_fkey foreign key (round_id, event_id)
    references public.rounds (id, event_id) on delete cascade,
  constraint correction_requests_room_fkey foreign key (room_id, event_id)
    references public.rooms (id, event_id) on delete cascade
);

-- "Avoid multiple conflicting active correction requests for the same
-- authoritative result" — one PENDING request per current_result_id.
create unique index correction_requests_one_pending_per_result
  on public.correction_requests (current_result_id) where status = 'PENDING';

create index correction_requests_room_idx on public.correction_requests (room_id);
create index correction_requests_round_idx on public.correction_requests (round_id);

alter table public.correction_requests enable row level security;
grant select, insert, update on public.correction_requests to anon, authenticated, service_role;

comment on table public.correction_requests is
  'A coordinator''s request to correct an already-confirmed round result
   (EVENT-OPS.md §14). Append-only except for the single PENDING -> APPROVED
   or PENDING -> REJECTED transition (correction_requests_refuse_update
   below) — a decision, once made, is never revisited by editing this row.';

-- Append-only except for the one legitimate transition: PENDING to a
-- decided state, setting decided_by/decided_at/decision_note and nothing
-- else. Same shape as results_update_guard/ledger_update_guard (0009) —
-- one narrow, explicit exception to an otherwise-refused UPDATE.
create or replace function public.correction_requests_refuse_update()
returns trigger language plpgsql as $$
begin
  if old.status = 'PENDING' and new.status in ('APPROVED', 'REJECTED')
     and new.id is not distinct from old.id
     and new.event_id is not distinct from old.event_id
     and new.room_id is not distinct from old.room_id
     and new.round_id is not distinct from old.round_id
     and new.current_result_id is not distinct from old.current_result_id
     and new.requested_by is not distinct from old.requested_by
     and new.reason is not distinct from old.reason
     and new.proposed_payload is not distinct from old.proposed_payload
     and new.created_at is not distinct from old.created_at
  then
    return new;
  end if;
  raise exception 'rows in % are append-only except for the single PENDING decision transition', tg_table_name
    using errcode = 'restrict_violation';
end;
$$;

create trigger correction_requests_refuse_update
  before update on public.correction_requests
  for each row execute function public.correction_requests_refuse_update();

create trigger correction_requests_refuse_delete
  before delete on public.correction_requests
  for each row execute function public.refuse_delete();

-- ============================================================ 2. shared correction applier

-- Internal (not granted to authenticated). The one place the actual
-- "supersede -> replace -> re-settle" mechanics live — admin_approve_correction
-- and admin_direct_correction both call this instead of duplicating
-- submit_round_result's correction logic a second and third time. Requires
-- an already-confirmed result to exist (a correction has nothing to
-- correct otherwise) and applies the same validate_round_payload() every
-- other write path uses.
create or replace function public.apply_round_correction(
  p_round_id uuid,
  p_payload jsonb,
  p_actor_uid uuid,
  p_audit_action text,
  p_audit_extra jsonb
) returns public.results
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_round record;
  v_existing_result record;
  v_new_result public.results;
  v_new_result_id uuid := gen_random_uuid();
  v_room_event_game record;
begin
  select r.*, eg.scoring_template as event_game_scoring_template into v_round
    from rounds r join event_games eg on eg.id = r.event_game_id
   where r.id = p_round_id for update of r;
  if not found then
    raise exception 'round_not_found: no such round' using errcode = 'no_data_found';
  end if;

  select * into v_existing_result from results
   where round_id = p_round_id and superseded_at is null for update;
  if v_existing_result.id is null then
    raise exception 'no_confirmed_result: this round has no confirmed result to correct' using errcode = '55000';
  end if;

  perform 1 from public.validate_round_payload(p_round_id, p_payload) limit 1;

  update results set superseded_at = now(), superseded_by = v_new_result_id where id = v_existing_result.id;

  insert into results (id, event_id, round_id, template, payload, idempotency_key, submitted_by)
  values (v_new_result_id, v_round.event_id, p_round_id, v_round.event_game_scoring_template, p_payload,
          'correction-' || v_new_result_id::text, p_actor_uid)
  returning * into v_new_result;

  update round_participants rp
     set participation = v.participation, role_key = v.role_key, raw_score = v.raw_score
    from public.validate_round_payload(p_round_id, p_payload) v
   where rp.round_id = p_round_id and rp.registration_id = v.registration_id;

  update rounds set status = 'COMPLETE', ended_at = coalesce(ended_at, now()) where id = p_round_id;

  insert into audit_logs (event_id, actor_user_id, action, entity_type, entity_id, before, after)
  values (v_round.event_id, p_actor_uid, p_audit_action, 'results', v_new_result.id,
          jsonb_build_object('previousResultId', v_existing_result.id),
          jsonb_build_object('roundId', p_round_id, 'payload', p_payload) || coalesce(p_audit_extra, '{}'::jsonb));

  -- SCORING.md §13 steps 3-9 — re-settle immediately if this room-game was
  -- already settled, not on some later action that may never come.
  select * into v_room_event_game
    from room_event_games where room_id = v_round.room_id and event_game_id = v_round.event_game_id;
  if found and v_room_event_game.status = 'COMPLETE' then
    perform public.settle_room_game_now(v_round.room_id, v_round.event_game_id);
  end if;

  return v_new_result;
end;
$$;

revoke all on function public.apply_round_correction(uuid, jsonb, uuid, text, jsonb) from public;

-- ============================================================ 3. request_result_correction

create or replace function public.request_result_correction(
  p_round_id uuid,
  p_proposed_payload jsonb,
  p_reason text
) returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_uid uuid := auth.uid();
  v_round record;
  v_current_result record;
  v_request public.correction_requests;
begin
  -- event_id/room_id are resolved here, server-side, from p_round_id —
  -- never accepted as separate client-supplied parameters that could
  -- disagree with the round's real owners.
  select r.event_id, r.room_id into v_round from rounds r where r.id = p_round_id;
  if v_round.room_id is null then
    raise exception 'round_not_found: no such round' using errcode = 'no_data_found';
  end if;

  if not public.is_authorized_for_room(v_round.room_id) then
    raise exception 'not_authorized: not this room''s coordinator or an event admin' using errcode = '42501';
  end if;

  if btrim(coalesce(p_reason, '')) = '' then
    raise exception 'invalid_reason: a reason is required to request a correction' using errcode = '22023';
  end if;

  select * into v_current_result from results
   where round_id = p_round_id and superseded_at is null;
  if not found then
    raise exception 'no_confirmed_result: this round has no confirmed result to correct' using errcode = '55000';
  end if;

  -- Same validation every other write path uses — a correction request
  -- cannot propose something submit_round_result itself would reject.
  perform 1 from public.validate_round_payload(p_round_id, p_proposed_payload) limit 1;

  if exists (select 1 from correction_requests where current_result_id = v_current_result.id and status = 'PENDING') then
    raise exception 'correction_already_pending: a correction request for this result is already pending Admin review'
      using errcode = '55000';
  end if;

  insert into correction_requests (event_id, room_id, round_id, current_result_id, requested_by, reason, proposed_payload)
  values (v_round.event_id, v_round.room_id, p_round_id, v_current_result.id, v_uid, p_reason, p_proposed_payload)
  returning * into v_request;

  insert into audit_logs (event_id, actor_user_id, action, entity_type, entity_id, after)
  values (v_round.event_id, v_uid, 'correction_request.created', 'correction_requests', v_request.id,
          jsonb_build_object('roundId', p_round_id, 'currentResultId', v_current_result.id, 'reason', p_reason));

  return jsonb_build_object('requestId', v_request.id, 'status', v_request.status);
end;
$$;

revoke all on function public.request_result_correction(uuid, jsonb, text) from public;
grant execute on function public.request_result_correction(uuid, jsonb, text) to authenticated;

-- ============================================================ 4. admin_approve_correction

create or replace function public.admin_approve_correction(p_request_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_uid uuid := auth.uid();
  v_request record;
  v_current_result_id uuid;
  v_new_result public.results;
begin
  perform public.require_event_admin();

  select * into v_request from correction_requests where id = p_request_id for update;
  if not found then
    raise exception 'correction_request_not_found: no such correction request' using errcode = 'no_data_found';
  end if;

  if v_request.status = 'APPROVED' then
    -- Idempotent: an accidental double-approve returns the already-applied
    -- outcome rather than re-applying (which apply_round_correction's own
    -- "requires a confirmed result to correct" guard would in any case
    -- refuse the second time, since the correction it already produced is
    -- itself now the confirmed result).
    return jsonb_build_object('requestId', v_request.id, 'status', v_request.status, 'idempotent', true);
  end if;
  if v_request.status = 'REJECTED' then
    raise exception 'correction_already_rejected: this request was already rejected and cannot now be approved'
      using errcode = '55000';
  end if;

  -- Stale check: the round's current authoritative result must still be
  -- exactly the one this request was raised against. If it has changed
  -- (another correction landed first), this request no longer describes a
  -- real edit to the current truth and must not be blindly applied.
  select id into v_current_result_id from results
   where round_id = v_request.round_id and superseded_at is null;
  if v_current_result_id is distinct from v_request.current_result_id then
    raise exception 'stale_correction_request: the authoritative result has changed since this request was created'
      using errcode = '55000';
  end if;

  v_new_result := public.apply_round_correction(
    v_request.round_id, v_request.proposed_payload, v_uid, 'correction_request.approved',
    jsonb_build_object('correctionRequestId', v_request.id, 'reason', v_request.reason)
  );

  update correction_requests
     set status = 'APPROVED', decided_by = v_uid, decided_at = now()
   where id = p_request_id;

  return jsonb_build_object('requestId', v_request.id, 'status', 'APPROVED', 'resultId', v_new_result.id, 'idempotent', false);
end;
$$;

revoke all on function public.admin_approve_correction(uuid) from public;
grant execute on function public.admin_approve_correction(uuid) to authenticated;

-- ============================================================ 5. admin_reject_correction

create or replace function public.admin_reject_correction(p_request_id uuid, p_note text default null)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_uid uuid := auth.uid();
  v_request record;
begin
  perform public.require_event_admin();

  select * into v_request from correction_requests where id = p_request_id for update;
  if not found then
    raise exception 'correction_request_not_found: no such correction request' using errcode = 'no_data_found';
  end if;

  if v_request.status = 'REJECTED' then
    return jsonb_build_object('requestId', v_request.id, 'status', v_request.status, 'idempotent', true);
  end if;
  if v_request.status = 'APPROVED' then
    raise exception 'correction_already_approved: this request was already approved and cannot now be rejected'
      using errcode = '55000';
  end if;

  update correction_requests
     set status = 'REJECTED', decided_by = v_uid, decided_at = now(), decision_note = p_note
   where id = p_request_id;

  insert into audit_logs (event_id, actor_user_id, action, entity_type, entity_id, after)
  values (v_request.event_id, v_uid, 'correction_request.rejected', 'correction_requests', v_request.id,
          jsonb_build_object('note', p_note));

  return jsonb_build_object('requestId', v_request.id, 'status', 'REJECTED', 'idempotent', false);
end;
$$;

revoke all on function public.admin_reject_correction(uuid, text) from public;
grant execute on function public.admin_reject_correction(uuid, text) to authenticated;

-- ============================================================ 6. admin_direct_correction

-- Admin's own correction path — EVENT-OPS.md §14's third option ("create a
-- direct Admin correction"), no coordinator request involved at all. Uses
-- the same shared applier as approval; requires a reason exactly like a
-- coordinator's request does.
create or replace function public.admin_direct_correction(
  p_round_id uuid,
  p_payload jsonb,
  p_reason text
) returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_uid uuid := auth.uid();
  v_new_result public.results;
begin
  perform public.require_event_admin();

  if btrim(coalesce(p_reason, '')) = '' then
    raise exception 'invalid_reason: a reason is required for a direct Admin correction' using errcode = '22023';
  end if;

  v_new_result := public.apply_round_correction(
    p_round_id, p_payload, v_uid, 'result.admin_direct_correction', jsonb_build_object('reason', p_reason)
  );

  return jsonb_build_object('roundId', p_round_id, 'resultId', v_new_result.id);
end;
$$;

revoke all on function public.admin_direct_correction(uuid, jsonb, text) from public;
grant execute on function public.admin_direct_correction(uuid, jsonb, text) to authenticated;

-- ============================================================ 7. submit_round_result

-- Same signature and same first-confirmation behavior as 0027's version.
-- The one change: when a confirmed (non-superseded) result already exists
-- for this round, this function now refuses uniformly — regardless of
-- whether the caller is a room coordinator or an event admin — rather than
-- silently superseding it. "Don't make the coordinator-facing submission
-- RPC silently privileged": an Admin correcting a result now goes through
-- admin_direct_correction (or approves a coordinator's request), not
-- through this function gaining a quiet admin-only exception.
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

  -- Idempotency check first, and still keyed to the SAME round only
  -- (0027) — a genuine retry (same key, same round) must keep working
  -- even though a confirmed result already exists; only a *new* payload
  -- attempting to supersede an existing confirmed result is what the next
  -- block refuses.
  select * into v_existing_by_key from results where idempotency_key = p_idempotency_key;
  if found then
    if v_existing_by_key.round_id <> p_round_id then
      raise exception 'idempotency_key_reused: this idempotency key already belongs to a different round'
        using errcode = '22023';
    end if;
    return jsonb_build_object('roundId', v_existing_by_key.round_id, 'resultId', v_existing_by_key.id, 'idempotent', true);
  end if;

  select * into v_existing_result from results
   where round_id = p_round_id and superseded_at is null for update;
  if v_existing_result.id is not null then
    raise exception 'correction_requires_request: a confirmed result already exists for this round — request a correction instead of resubmitting'
      using errcode = '55000';
  end if;

  -- Validate first — nothing is written if the payload is bad.
  perform 1 from public.validate_round_payload(p_round_id, p_payload) limit 1;

  insert into results (id, event_id, round_id, template, payload, idempotency_key, submitted_by)
  values (v_new_result_id, v_round.event_id, p_round_id, v_round.event_game_scoring_template, p_payload, p_idempotency_key, v_uid)
  returning * into v_new_result;

  update round_participants rp
     set participation = v.participation, role_key = v.role_key, raw_score = v.raw_score
    from public.validate_round_payload(p_round_id, p_payload) v
   where rp.round_id = p_round_id and rp.registration_id = v.registration_id;

  update rounds set status = 'COMPLETE', ended_at = coalesce(ended_at, now()) where id = p_round_id;

  insert into audit_logs (event_id, actor_user_id, action, entity_type, entity_id, after)
  values (v_round.event_id, v_uid, 'result.submitted', 'results', v_new_result.id,
          jsonb_build_object('roundId', p_round_id, 'payload', p_payload));

  return jsonb_build_object('roundId', p_round_id, 'resultId', v_new_result.id, 'idempotent', false, 'corrected', false);
end;
$$;

-- ============================================================ 8. complete_room_game

-- Same signature and authorization as before. Adds the actual completion
-- gate EVENT-OPS.md §5 describes but 0025 never enforced: normal
-- completion requires EITHER the configured round count to be reached OR
-- (when a duration is configured) the game window to have expired — not
-- merely "no round is currently live," which any coordinator could reach
-- after a single round regardless of the other 2 planned. VOID rounds
-- still never count toward the round-count condition (0027, §9) — a
-- crashed-and-replayed round is not a real 1-of-N contribution to "have we
-- reached the configured number." No Admin-only early-finish override is
-- added here: the brief leaves that conditional on the architecture
-- genuinely needing one, and inventing an unrequested bypass is exactly
-- the risk it warns against — Admin recourse for now is the same as
-- everyone else's: reach the round count, or wait out the window.
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
  v_event_game record;
  v_completed_count integer;
  v_window_expired boolean;
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

  select * into v_event_game from event_games where id = p_event_game_id;

  select count(*) into v_completed_count from rounds
   where room_id = p_room_id and event_game_id = p_event_game_id and status = 'COMPLETE';

  v_window_expired := v_event_game.duration_minutes is not null
    and v_row.started_at is not null
    and now() > v_row.started_at + (v_event_game.duration_minutes || ' minutes')::interval;

  if v_completed_count < v_event_game.planned_rounds and not v_window_expired then
    raise exception 'room_game_not_ready: this room has completed % of % planned round(s) and the game window has not expired', v_completed_count, v_event_game.planned_rounds
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
