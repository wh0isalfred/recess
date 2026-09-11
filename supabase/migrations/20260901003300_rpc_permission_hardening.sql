-- 0033 — Pre-Phase-9 hotfix: RPC execution permission hardening.
--
-- The production Supabase security advisor found SECURITY DEFINER
-- functions callable by roles they were never intended to expose to.
-- Direct inspection confirmed it: every prior migration's own grant
-- pattern was `revoke all ... from public` followed by a selective
-- `grant ... to authenticated` — but PUBLIC and the actual `anon`/
-- `authenticated` roles are not the same revocation target. A role can
-- hold EXECUTE independently of PUBLIC (Supabase's own project-level
-- default-privileges configuration is the most likely source here,
-- since it is common practice for Supabase projects to grant EXECUTE on
-- new functions to `anon`/`authenticated` automatically at creation
-- time — entirely outside any migration file this repository controls).
-- `revoke all from public` never touches a grant made that way.
--
-- Confirmed directly, not assumed: 15 functions in this repository have
-- NEVER had a single grant/revoke statement issued against them in any
-- migration — meaning they currently sit at Postgres's own default
-- privilege state, EXECUTE granted to PUBLIC, unconditionally. All 15
-- are internal trigger/validation functions with no business being
-- directly callable at all.
--
-- This migration is grant/revoke statements only for every function
-- that already exists correctly — no scoring formula, authorization
-- rule, or computation changes anywhere. The one exception: 14 internal
-- helper/trigger functions found with no `search_path` set at all (a
-- real, separate advisor-flagged weakness on SECURITY DEFINER/PL-pgSQL
-- functions) are re-created here with `set search_path = public,
-- pg_temp` added — and nothing else in their bodies changed, confirmed
-- by diffing each against its prior definition.
--
-- Default-deny throughout: every function below gets an explicit
-- `revoke execute ... from public, anon, authenticated` first, then
-- exactly the intended surface is granted back — never relying on
-- `revoke all from public` alone again.

-- ============================================================================
-- SEARCH_PATH HARDENING — 14 internal helper/trigger functions with no
-- search_path previously set. Bodies unchanged except for that one
-- addition; diffed against each function's prior definition to confirm.
-- ============================================================================

create or replace function public.audit_game_alias()
returns trigger language plpgsql set search_path = public, pg_temp as $$
declare
  v_row    public.game_aliases := coalesce(new, old);
  v_action text := case tg_op
                     when 'INSERT' then 'game_alias.created'
                     when 'UPDATE' then 'game_alias.changed'
                     else 'game_alias.deleted'
                   end;
begin
  insert into public.audit_logs (
    event_id, actor_user_id, action, entity_type, entity_id, before, after
  ) values (
    -- Resolved through the events table so a cascade delete of a DRAFT event
    -- records the alias removal without a dangling reference.
    (select id from public.events where id = v_row.event_id),
    auth.uid(),
    v_action,
    'game_aliases',
    v_row.id,
    case when tg_op = 'INSERT' then null
         else jsonb_build_object('alias', old.alias) end,
    case when tg_op = 'DELETE' then null
         else jsonb_build_object('alias', new.alias) end
  );
  return coalesce(new, old);
end;
$$;

create or replace function public.audit_logs_allow_event_unlink()
returns trigger
language plpgsql
set search_path = public, pg_temp
as $$
begin
  if new.event_id is null
     and old.event_id is not null
     and new.id                    is not distinct from old.id
     and new.actor_user_id         is not distinct from old.actor_user_id
     and new.actor_registration_id is not distinct from old.actor_registration_id
     and new.action                is not distinct from old.action
     and new.entity_type           is not distinct from old.entity_type
     and new.entity_id              is not distinct from old.entity_id
     and new.before                is not distinct from old.before
     and new.after                 is not distinct from old.after
     and new.created_at            is not distinct from old.created_at
  then
    -- Exactly the FK's own SET NULL action on event_id and nothing else —
    -- allow it through unchanged.
    return new;
  end if;

  raise exception 'rows in % are append-only and cannot be updated', tg_table_name
    using errcode = 'restrict_violation';
end;
$$;

create or replace function public.correction_requests_refuse_update()
returns trigger language plpgsql set search_path = public, pg_temp as $$
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

create or replace function public.create_event_counter()
returns trigger language plpgsql set search_path = public, pg_temp as $$
begin
  insert into public.event_counters (event_id) values (new.id);
  return new;
end;
$$;

create or replace function public.event_transition_is_legal(
  p_from public.event_status,
  p_to   public.event_status
) returns boolean language sql immutable set search_path = public, pg_temp as $$
  select (p_from, p_to) in (
    ('DRAFT',              'REGISTRATION'),
    ('DRAFT',              'CANCELLED'),
    ('REGISTRATION',       'DRAFT'),
    ('REGISTRATION',       'REGISTRATION_CLOSED'),
    ('REGISTRATION',       'CHECK_IN'),
    ('REGISTRATION',       'CANCELLED'),
    ('REGISTRATION_CLOSED','REGISTRATION'),
    ('REGISTRATION_CLOSED','CHECK_IN'),
    ('REGISTRATION_CLOSED','CANCELLED'),
    ('CHECK_IN',           'REGISTRATION'),
    ('CHECK_IN',           'REGISTRATION_CLOSED'),
    ('CHECK_IN',           'LIVE'),
    ('CHECK_IN',           'CANCELLED'),
    ('LIVE',               'CHECK_IN'),
    ('LIVE',               'PAUSED'),
    ('LIVE',               'COMPLETE'),
    ('LIVE',               'CANCELLED'),
    ('PAUSED',             'LIVE'),
    ('PAUSED',             'COMPLETE'),
    ('PAUSED',             'CANCELLED'),
    ('COMPLETE',           'LIVE')
  );
$$;

create or replace function public.events_draft_only_delete()
returns trigger language plpgsql set search_path = public, pg_temp as $$
begin
  if old.status not in ('DRAFT', 'REGISTRATION', 'REGISTRATION_CLOSED') then
    raise exception 'event % is % and cannot be deleted; cancel it instead', old.slug, old.status
      using errcode = 'restrict_violation';
  end if;
  if exists (select 1 from public.results where event_id = old.id)
     or exists (select 1 from public.point_transactions where event_id = old.id) then
    raise exception 'event % has real scoring history and cannot be deleted; cancel it instead', old.slug
      using errcode = 'restrict_violation';
  end if;
  return old;
end;
$$;

create or replace function public.events_status_guard()
returns trigger language plpgsql set search_path = public, pg_temp as $$
begin
  if new.status is distinct from old.status
     and coalesce(current_setting('recess.allow_status_change', true), '0') <> '1'
  then
    raise exception 'events.status may only be changed by transition_event()'
      using errcode = 'restrict_violation';
  end if;
  return new;
end;
$$;

create or replace function public.is_whatsapp_group_url(p_url text)
returns boolean language sql immutable set search_path = public, pg_temp as $$
  -- https://chat.whatsapp.com/<code> and the older /invite/<code> form.
  -- Anchored at both ends, so a lookalike host such as
  -- https://chat.whatsapp.com.example.com/AbC is rejected.
  select p_url ~ '^https://chat\.whatsapp\.com/(invite/)?[A-Za-z0-9_-]{6,64}$';
$$;

create or replace function public.ledger_update_guard()
returns trigger language plpgsql set search_path = public, pg_temp as $$
begin
  if old.voided_at is not null then
    raise exception 'point_transactions row % is already voided and is immutable', old.id
      using errcode = 'restrict_violation';
  end if;

  if (new.id, new.event_id, new.registration_id, new.points, new.source,
      new.result_id, new.round_id, new.event_game_id, new.note,
      new.created_by, new.created_at)
     is distinct from
     (old.id, old.event_id, old.registration_id, old.points, old.source,
      old.result_id, old.round_id, old.event_game_id, old.note,
      old.created_by, old.created_at)
  then
    raise exception 'point_transactions is append-only; only voided_at/voided_by may be set'
      using errcode = 'restrict_violation';
  end if;

  if new.voided_at is null then
    raise exception 'the only permitted update to point_transactions is voiding'
      using errcode = 'restrict_violation';
  end if;

  return new;
end;
$$;

create or replace function public.refuse_delete()
returns trigger language plpgsql set search_path = public, pg_temp as $$
begin
  raise exception 'rows in % are append-only and cannot be deleted', tg_table_name
    using errcode = 'restrict_violation';
end;
$$;

create or replace function public.refuse_update()
returns trigger language plpgsql set search_path = public, pg_temp as $$
begin
  raise exception 'rows in % are append-only and cannot be updated', tg_table_name
    using errcode = 'restrict_violation';
end;
$$;

create or replace function public.results_update_guard()
returns trigger language plpgsql set search_path = public, pg_temp as $$
begin
  if old.superseded_at is not null then
    raise exception 'results row % is already superseded and is immutable', old.id
      using errcode = 'restrict_violation';
  end if;

  if (new.id, new.event_id, new.round_id, new.template, new.payload, new.version,
      new.idempotency_key, new.submitted_by, new.submitted_at, new.created_at)
     is distinct from
     (old.id, old.event_id, old.round_id, old.template, old.payload, old.version,
      old.idempotency_key, old.submitted_by, old.submitted_at, old.created_at)
  then
    raise exception 'results is append-only; only superseded_at/superseded_by may be set'
      using errcode = 'restrict_violation';
  end if;

  if new.superseded_at is null then
    raise exception 'the only permitted update to results is supersession'
      using errcode = 'restrict_violation';
  end if;

  return new;
end;
$$;

create or replace function public.set_updated_at()
returns trigger language plpgsql set search_path = public, pg_temp as $$
begin
  new.updated_at := now();
  return new;
end;
$$;

create or replace function public.validate_event_timezone()
returns trigger language plpgsql set search_path = public, pg_temp as $$
begin
  if not exists (select 1 from pg_timezone_names where name = new.timezone) then
    raise exception '% is not a valid IANA timezone name', new.timezone
      using errcode = 'check_violation';
  end if;
  return new;
end;
$$;
-- ============================================================================
-- INTERNAL ONLY — never callable directly by anon or authenticated.
-- Reachable only from within another SECURITY DEFINER function owned by
-- the same privileged role — PostgreSQL does not require the calling
-- client role to hold EXECUTE on a function called internally by a
-- SECURITY DEFINER function it doesn't have access to bypass anyway.
-- ============================================================================

revoke execute on function public.apply_round_correction(uuid, jsonb, uuid, text, jsonb) from public, anon, authenticated;
revoke execute on function public.assert_coordinator_eligible(uuid, uuid) from public, anon, authenticated;
revoke execute on function public.audit_game_alias() from public, anon, authenticated;
revoke execute on function public.audit_logs_allow_event_unlink() from public, anon, authenticated;
revoke execute on function public.correction_requests_refuse_update() from public, anon, authenticated;
revoke execute on function public.create_event_counter() from public, anon, authenticated;
revoke execute on function public.current_staff_role() from public, anon, authenticated;
revoke execute on function public.event_registrations_sync_identity() from public, anon, authenticated;
revoke execute on function public.event_transition_is_legal(public.event_status, public.event_status) from public, anon, authenticated;
revoke execute on function public.events_draft_only_delete() from public, anon, authenticated;
revoke execute on function public.events_status_guard() from public, anon, authenticated;
revoke execute on function public.is_authorized_for_room(uuid) from public, anon, authenticated;
revoke execute on function public.is_whatsapp_group_url(text) from public, anon, authenticated;
revoke execute on function public.ledger_update_guard() from public, anon, authenticated;
revoke execute on function public.refuse_delete() from public, anon, authenticated;
revoke execute on function public.refuse_update() from public, anon, authenticated;
revoke execute on function public.require_event_admin() from public, anon, authenticated;
revoke execute on function public.results_update_guard() from public, anon, authenticated;
revoke execute on function public.room_game_ready_to_settle(uuid, uuid) from public, anon, authenticated;
revoke execute on function public.room_standings_compute(uuid, uuid) from public, anon, authenticated;
revoke execute on function public.set_updated_at() from public, anon, authenticated;
revoke execute on function public.settle_room_game_now(uuid, uuid) from public, anon, authenticated;
revoke execute on function public.transition_event(uuid, public.event_status, text) from public, anon, authenticated;
revoke execute on function public.validate_event_timezone() from public, anon, authenticated;
revoke execute on function public.validate_round_payload(uuid, jsonb) from public, anon, authenticated;

-- ============================================================================
-- PLAYER FACING — authenticated only. Every anonymous RECESS player
-- session is a real Supabase Auth session executing as `authenticated`,
-- never as the database `anon` role — an anonymously-signed-in Auth user
-- is not the same thing as the Postgres `anon` role. None of these need
-- pre-auth (`anon`) access.
-- ============================================================================

revoke execute on function public.check_in_player() from public, anon, authenticated;
revoke execute on function public.current_player_id() from public, anon, authenticated;
revoke execute on function public.get_my_game_progress() from public, anon, authenticated;
revoke execute on function public.get_my_registration() from public, anon, authenticated;
revoke execute on function public.get_my_room_standings() from public, anon, authenticated;
revoke execute on function public.get_player_state() from public, anon, authenticated;
revoke execute on function public.recover_player_access() from public, anon, authenticated;
revoke execute on function public.register_player(text, text, text, text, boolean) from public, anon, authenticated;
grant execute on function public.check_in_player() to authenticated;
grant execute on function public.current_player_id() to authenticated;
grant execute on function public.get_my_game_progress() to authenticated;
grant execute on function public.get_my_registration() to authenticated;
grant execute on function public.get_my_room_standings() to authenticated;
grant execute on function public.get_player_state() to authenticated;
grant execute on function public.recover_player_access() to authenticated;
grant execute on function public.register_player(text, text, text, text, boolean) to authenticated;

-- ============================================================================
-- COORDINATOR FACING — authenticated only. A coordinator is a normal
-- authenticated RECESS player; each function below enforces its own room
-- authorization internally via is_authorized_for_room() (or, for
-- correction/void paths, the equivalent round/room derivation) — the
-- grant here is necessary but never sufficient on its own.
-- ============================================================================

revoke execute on function public.complete_room_game(uuid, uuid) from public, anon, authenticated;
revoke execute on function public.coordinator_room_standings(uuid) from public, anon, authenticated;
revoke execute on function public.coordinator_room_state(uuid) from public, anon, authenticated;
revoke execute on function public.preview_round_result(uuid, jsonb) from public, anon, authenticated;
revoke execute on function public.request_result_correction(uuid, jsonb, text) from public, anon, authenticated;
revoke execute on function public.start_room_game(uuid, uuid) from public, anon, authenticated;
revoke execute on function public.start_round(uuid, uuid) from public, anon, authenticated;
revoke execute on function public.submit_round_result(uuid, jsonb, text) from public, anon, authenticated;
revoke execute on function public.void_round(uuid, text) from public, anon, authenticated;
grant execute on function public.complete_room_game(uuid, uuid) to authenticated;
grant execute on function public.coordinator_room_standings(uuid) to authenticated;
grant execute on function public.coordinator_room_state(uuid) to authenticated;
grant execute on function public.preview_round_result(uuid, jsonb) to authenticated;
grant execute on function public.request_result_correction(uuid, jsonb, text) to authenticated;
grant execute on function public.start_room_game(uuid, uuid) to authenticated;
grant execute on function public.start_round(uuid, uuid) to authenticated;
grant execute on function public.submit_round_result(uuid, jsonb, text) to authenticated;
grant execute on function public.void_round(uuid, text) to authenticated;

-- ============================================================================
-- STAFF / ADMIN FACING — authenticated only, never anon. Staff accounts
-- are themselves authenticated users; the EXECUTE grant and the internal
-- require_event_admin()/current_staff_role() check are deliberately
-- separate layers — every function below was confirmed, not assumed, to
-- perform its own staff check before doing anything privileged.
-- ============================================================================

revoke execute on function public.admin_add_event_game(text, uuid, integer, integer, integer) from public, anon, authenticated;
revoke execute on function public.admin_approve_correction(uuid) from public, anon, authenticated;
revoke execute on function public.admin_assign_coordinator(text, uuid, uuid) from public, anon, authenticated;
revoke execute on function public.admin_assign_waiting_players(text) from public, anon, authenticated;
revoke execute on function public.admin_create_event(text, text, timestamptz, text, text, timestamptz, timestamptz, timestamptz, timestamptz, integer, text) from public, anon, authenticated;
revoke execute on function public.admin_create_room(text, text, integer, uuid, text) from public, anon, authenticated;
revoke execute on function public.admin_delete_event(text) from public, anon, authenticated;
revoke execute on function public.admin_direct_correction(uuid, jsonb, text) from public, anon, authenticated;
revoke execute on function public.admin_event_overview(text) from public, anon, authenticated;
revoke execute on function public.admin_get_event(text) from public, anon, authenticated;
revoke execute on function public.admin_list_coordinator_candidates(text) from public, anon, authenticated;
revoke execute on function public.admin_list_event_games(text) from public, anon, authenticated;
revoke execute on function public.admin_list_events() from public, anon, authenticated;
revoke execute on function public.admin_list_games() from public, anon, authenticated;
revoke execute on function public.admin_list_rooms(text) from public, anon, authenticated;
revoke execute on function public.admin_manual_adjustment(text, uuid, integer, text) from public, anon, authenticated;
revoke execute on function public.admin_open_check_in(text) from public, anon, authenticated;
revoke execute on function public.admin_open_registration(text) from public, anon, authenticated;
revoke execute on function public.admin_purge_pre_event(text) from public, anon, authenticated;
revoke execute on function public.admin_reject_correction(uuid, text) from public, anon, authenticated;
revoke execute on function public.admin_replace_room_coordinator(text, uuid, uuid) from public, anon, authenticated;
revoke execute on function public.admin_room_members(uuid) from public, anon, authenticated;
revoke execute on function public.admin_update_event_game(text, uuid, integer, integer) from public, anon, authenticated;
revoke execute on function public.admin_upsert_room(text, uuid, text, integer, text) from public, anon, authenticated;
revoke execute on function public.get_my_staff_profile() from public, anon, authenticated;
revoke execute on function public.room_standings(uuid) from public, anon, authenticated;
grant execute on function public.admin_add_event_game(text, uuid, integer, integer, integer) to authenticated;
grant execute on function public.admin_approve_correction(uuid) to authenticated;
grant execute on function public.admin_assign_coordinator(text, uuid, uuid) to authenticated;
grant execute on function public.admin_assign_waiting_players(text) to authenticated;
grant execute on function public.admin_create_event(text, text, timestamptz, text, text, timestamptz, timestamptz, timestamptz, timestamptz, integer, text) to authenticated;
grant execute on function public.admin_create_room(text, text, integer, uuid, text) to authenticated;
grant execute on function public.admin_delete_event(text) to authenticated;
grant execute on function public.admin_direct_correction(uuid, jsonb, text) to authenticated;
grant execute on function public.admin_event_overview(text) to authenticated;
grant execute on function public.admin_get_event(text) to authenticated;
grant execute on function public.admin_list_coordinator_candidates(text) to authenticated;
grant execute on function public.admin_list_event_games(text) to authenticated;
grant execute on function public.admin_list_events() to authenticated;
grant execute on function public.admin_list_games() to authenticated;
grant execute on function public.admin_list_rooms(text) to authenticated;
grant execute on function public.admin_manual_adjustment(text, uuid, integer, text) to authenticated;
grant execute on function public.admin_open_check_in(text) to authenticated;
grant execute on function public.admin_open_registration(text) to authenticated;
grant execute on function public.admin_purge_pre_event(text) to authenticated;
grant execute on function public.admin_reject_correction(uuid, text) to authenticated;
grant execute on function public.admin_replace_room_coordinator(text, uuid, uuid) to authenticated;
grant execute on function public.admin_room_members(uuid) to authenticated;
grant execute on function public.admin_update_event_game(text, uuid, integer, integer) to authenticated;
grant execute on function public.admin_upsert_room(text, uuid, text, integer, text) to authenticated;
grant execute on function public.get_my_staff_profile() to authenticated;
grant execute on function public.room_standings(uuid) to authenticated;

-- ============================================================================
-- PUBLIC / PRE-AUTH — deliberately empty. No function in this codebase
-- genuinely requires execution before a Supabase Auth session exists;
-- even the very first registration call (register_player()) runs under
-- an already-established anonymous Auth session, i.e. as `authenticated`.
-- ============================================================================
