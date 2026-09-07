-- 0022 — fix a real schema contradiction found in testing: deleting a DRAFT
-- event fails.
--
-- audit_logs.event_id is `references events(id) on delete set null` —
-- deliberately not CASCADE, so audit history outlives the event it was
-- about (EVENT-OPS.md's whole audit posture depends on history surviving
-- the record it describes). But audit_logs also has a blanket
-- `before update ... refuse_update()` trigger making the table fully
-- append-only. When an event is deleted, Postgres enforces the FK action by
-- issuing a real UPDATE (`event_id = null`) against every audit_logs row
-- that referenced it — and the generic trigger refuses that UPDATE like
-- any other, so the DELETE on events fails outright, for every event
-- regardless of status.
--
-- The fix is narrow and audit_logs-specific: a dedicated trigger function
-- that allows exactly one shape of update — event_id changing from a real
-- value to null, with every other column byte-identical to before — and
-- refuses everything else exactly as the old shared refuse_update() did.
-- This is not a policy loosening of "audit rows can be edited"; nulling a
-- dangling reference after its parent is gone is a referential-integrity
-- action, not an edit to the fact the row records. The shared
-- refuse_update()/refuse_delete() functions themselves are untouched, so
-- every other append-only table (results, point_transactions, and
-- audit_logs' own delete trigger) keeps exactly the immutability it has
-- today — this migration does not touch them.
--
-- Also adds admin_delete_event(): the only way this situation can arise in
-- practice is Admin deleting an event, so the RPC and the schema fix belong
-- in the same migration. DRAFT-only, by design — EVENT-OPS.md never
-- describes deleting a real, running, or completed event, only ever
-- cancelling one (the existing CANCELLED status/transition already covers
-- that). Every other FK referencing events.id is already ON DELETE CASCADE
-- (event_counters, event_registrations, event_games, rooms,
-- room_memberships, awards, room_coordinators, room_event_games — checked
-- against every migration before writing this), so a DRAFT event's own
-- not-yet-real children are correctly removed with it; audit_logs is the
-- one table designed to survive, which is exactly what this migration makes
-- actually possible.

-- ---------------------------------------------------- dedicated trigger

create or replace function public.audit_logs_allow_event_unlink()
returns trigger
language plpgsql
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

comment on function public.audit_logs_allow_event_unlink() is
  'audit_logs-specific replacement for the shared refuse_update() trigger.
   Permits exactly one update shape — event_id: <value> -> null, nothing
   else changed — which is what events.id''s ON DELETE SET NULL action
   performs when its parent event is deleted. Every other update shape,
   including one that also nulls event_id while changing anything else, is
   still refused. The shared refuse_update()/refuse_delete() functions used
   by other append-only tables are not modified by this migration.';

drop trigger audit_logs_refuse_update on public.audit_logs;

create trigger audit_logs_refuse_update
  before update on public.audit_logs
  for each row execute function public.audit_logs_allow_event_unlink();

-- audit_logs_refuse_delete (refuse_delete()) is untouched — audit rows
-- still can never be deleted, only have their event_id nulled by the one
-- permitted path above.

-- ---------------------------------------------------- admin_delete_event

create or replace function public.admin_delete_event(p_event_slug text)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_uid uuid := auth.uid();
  v_event record;
begin
  perform public.require_event_admin();

  select * into v_event from events where slug = p_event_slug;
  if not found then
    raise exception 'event_not_found: no such event' using errcode = 'no_data_found';
  end if;

  if v_event.status <> 'DRAFT' then
    raise exception 'event_not_draft: only a DRAFT event can be deleted — cancel a live/registered event instead'
      using errcode = '55000';
  end if;

  -- Logged before the delete, with the real event_id, while it still
  -- exists to reference — the FK's SET NULL action (now actually able to
  -- run, per the fix above) nulls this row's event_id along with every
  -- other row that named this event, exactly like the rest of its history.
  insert into audit_logs (event_id, actor_user_id, action, entity_type, entity_id, before)
  values (v_event.id, v_uid, 'event.deleted', 'events', v_event.id,
          jsonb_build_object('slug', v_event.slug, 'name', v_event.name, 'status', v_event.status));

  delete from events where id = v_event.id;

  return jsonb_build_object('slug', v_event.slug, 'deleted', true);
end;
$$;

revoke all on function public.admin_delete_event(text) from public;
grant execute on function public.admin_delete_event(text) to authenticated;
