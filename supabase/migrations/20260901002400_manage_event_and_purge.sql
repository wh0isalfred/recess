-- 0024 — Manage Event: post-creation event-game editing support, and safe
-- permanent pre-event deletion.
--
-- Two independent pieces:
--
--   1. admin_list_event_games() — the full per-event-game list
--      (duration/rounds included) that no existing read returns.
--      admin_event_overview()'s own `nextGame` (0018) is deliberately left
--      alone: it's a single-game summary for the Overview dashboard, not a
--      list, and rewriting its shape would touch a screen this task isn't
--      about.
--
--   2. admin_purge_pre_event() — a new, separately named, SUPER_ADMIN-only
--      RPC for permanently deleting a pre-event-state event and everything
--      that cascades from it. admin_delete_event() (0022) is UNCHANGED —
--      still DRAFT-only, still EVENT_ADMIN-or-above, still exactly what it
--      was. Broadening its contract in place would have meant either
--      loosening its status check for every existing caller of that exact
--      function or overloading one name to mean two different safety
--      levels — both worse than one clearly-named function per policy.
--      "purge" names the destructive, SUPER_ADMIN-only operation this is;
--      "delete" stays the narrower, already-reviewed one.
--
-- Both reuse the audit-unlink mechanism 0022 already fixed at the database
-- level (the FK's own ON DELETE SET NULL + audit_logs_allow_event_unlink) —
-- neither function needs to do anything special for audit history beyond
-- writing its own audit row before deleting, exactly like
-- admin_delete_event() already does.

-- ------------------------------------------------------- events delete guard

-- 0004's events_draft_only_delete() is the real last line of defense behind
-- every DELETE on events — admin_delete_event()'s own DRAFT-only check
-- (0022) and admin_purge_pre_event()'s own broader check (below) both run
-- before this trigger, but this trigger is what actually enforces the
-- limit at the database level regardless of which function attempts the
-- delete. Discovered this the hard way: admin_purge_pre_event() initially
-- allowed REGISTRATION/REGISTRATION_CLOSED at the application level, but
-- the unwidened trigger still rejected the DELETE itself with its own
-- "cannot be deleted; cancel it instead" error, since it only ever
-- permitted DRAFT.
--
-- Widened here to match the policy this migration actually implements —
-- DRAFT, REGISTRATION, and REGISTRATION_CLOSED are all pre-event states a
-- SUPER_ADMIN may now permanently purge; CHECK_IN, LIVE, PAUSED, COMPLETE
-- and CANCELLED remain refused at this same database level, not just by
-- application-level checks above it. admin_delete_event() is unaffected —
-- its own DRAFT-only check still runs first and is strictly narrower than
-- what this trigger now permits, so nothing that function already refuses
-- becomes possible through it.
--
-- Status alone is not sufficient protection, and the existing test suite
-- caught this directly: a pre-existing test (05_history_and_rls.test.sql)
-- inserts results/point_transactions against a REGISTRATION-status event
-- specifically to prove real scoring history blocks deletion — status-only
-- widening would have let that history cascade away. This trigger now also
-- refuses deletion, at any status, if any results or point_transactions
-- row still references the event — the genuinely load-bearing check
-- "wide cascade from events is safe" actually depends on.
create or replace function public.events_draft_only_delete()
returns trigger language plpgsql as $$
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

-- ------------------------------------------------------ admin_list_event_games

create or replace function public.admin_list_event_games(p_event_slug text)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
declare
  v_event_id uuid;
begin
  perform public.require_event_admin();

  select id into v_event_id from events where slug = p_event_slug;
  if not found then
    raise exception 'event_not_found: no such event' using errcode = 'no_data_found';
  end if;

  return coalesce((
    select jsonb_agg(jsonb_build_object(
             'id', eg.id, 'gameSlug', g.slug, 'gameName', g.name, 'position', eg.position,
             'durationMinutes', eg.duration_minutes, 'plannedRounds', eg.planned_rounds
           ) order by eg.position)
      from event_games eg
      join games g on g.id = eg.game_id
     where eg.event_id = v_event_id
  ), '[]'::jsonb);
end;
$$;

revoke all on function public.admin_list_event_games(text) from public;
grant execute on function public.admin_list_event_games(text) to authenticated;

-- ------------------------------------------------------------ admin_purge_pre_event

-- SUPER_ADMIN only — deliberately not require_event_admin(), which also
-- admits EVENT_ADMIN. Permanent, irreversible deletion of real (if
-- pre-event) registrations is a higher bar than the day-to-day event-admin
-- operations that function guards.
--
-- Every check below re-resolves state itself rather than trusting a
-- client-supplied count or status — the client's earlier "fetch deletion
-- info" read (admin_event_overview, unchanged) is a preview for the
-- confirmation UI, never the authorization.
create or replace function public.admin_purge_pre_event(p_event_slug text)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_uid uuid := auth.uid();
  v_event record;
  v_registration_count int;
  v_checked_in_count int;
begin
  if public.current_staff_role() is distinct from 'SUPER_ADMIN' then
    raise exception 'not_authorized: SUPER_ADMIN required to permanently delete an event' using errcode = '42501';
  end if;

  select * into v_event from events where slug = p_event_slug for update;
  if not found then
    -- Idempotent, not an error state: a retried/double-submitted purge on
    -- an event that's already gone should read as "already deleted," not
    -- as a fresh failure — the end state (event does not exist) is what a
    -- second call actually wants to confirm.
    return jsonb_build_object('slug', p_event_slug, 'purged', true, 'alreadyDeleted', true);
  end if;

  if v_event.status not in ('DRAFT', 'REGISTRATION', 'REGISTRATION_CLOSED') then
    raise exception 'unsafe_lifecycle_state: only DRAFT, REGISTRATION or REGISTRATION_CLOSED events can be permanently deleted — cancel a live/completed event instead'
      using errcode = '55000';
  end if;

  select count(*) into v_checked_in_count
    from event_registrations where event_id = v_event.id and checked_in_at is not null;
  if v_checked_in_count > 0 then
    raise exception 'players_checked_in: this event has checked-in players and cannot be permanently deleted — cancel it instead'
      using errcode = '55000';
  end if;

  select count(*) into v_registration_count
    from event_registrations where event_id = v_event.id;

  -- Logged before the delete, with the real event_id, while it still
  -- exists to reference — same pattern admin_delete_event() already uses.
  -- The registration count is captured in the payload itself, since the
  -- rows it counted are gone a moment later.
  insert into audit_logs (event_id, actor_user_id, action, entity_type, entity_id, before)
  values (v_event.id, v_uid, 'event.purged', 'events', v_event.id,
          jsonb_build_object('slug', v_event.slug, 'name', v_event.name, 'status', v_event.status,
                              'registrationsRemoved', v_registration_count));

  -- Cascades to event_registrations, event_games, rooms, room_memberships,
  -- room_coordinators, room_event_games, event_counters, awards — every FK
  -- to events is ON DELETE CASCADE except audit_logs (SET NULL, above).
  -- players is never touched: it has no FK to events at all, only via
  -- event_registrations.player_id, so a player's own row is untouched no
  -- matter how many of their event registrations are removed.
  delete from events where id = v_event.id;

  return jsonb_build_object('slug', v_event.slug, 'purged', true, 'registrationsRemoved', v_registration_count);
end;
$$;

revoke all on function public.admin_purge_pre_event(text) from public;
grant execute on function public.admin_purge_pre_event(text) to authenticated;
