-- 0031 — Coordinator standings hotfix.
--
-- room_standings() gates on require_event_admin() — staff only, by its
-- own explicit design ("COORDINATOR is a real, existing role —
-- deliberately not admitted here"). The Phase 8 Coordinator Experience
-- frontend calls it anyway, expecting to see the coordinator's own room's
-- standings, and gets refused. The fix is not to loosen room_standings()
-- itself — its admin-only contract is intentional and stays exactly as
-- it was — but to add a second, narrower read for exactly the case the
-- coordinator UI actually needs: the coordinator's own room, nothing
-- else.
--
-- The standings computation itself is extracted once into an internal
-- helper so it exists in exactly one place — room_standings() and the
-- new coordinator_room_standings() both call it, rather than the same
-- ledger-derived query being maintained twice. No scoring formula,
-- qualification rule, or leaderboard_visibility behavior changes here;
-- this migration is authorization plumbing only.

-- ============================================================ 1. internal helper

-- Not granted to anon/authenticated — reachable only from within another
-- SECURITY DEFINER function (room_standings(), coordinator_room_standings()),
-- exactly like validate_round_payload() and apply_round_correction() are
-- internal-only for the same reason.
create or replace function public.room_standings_compute(p_room_id uuid, p_event_id uuid)
returns jsonb
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  with totals as (
    select rm.registration_id, coalesce(sum(pt.points), 0) as total_points
      from room_memberships rm
      left join point_transactions pt
        on pt.registration_id = rm.registration_id and pt.voided_at is null
       and pt.event_id = p_event_id
     where rm.room_id = p_room_id and rm.left_at is null
     group by rm.registration_id
  ),
  ranked as (
    select er.id, er.alias, t.total_points,
           rank() over (order by t.total_points desc) as placement
      from totals t
      join event_registrations er on er.id = t.registration_id
  )
  select coalesce(jsonb_agg(jsonb_build_object(
           'registrationId', id, 'alias', alias, 'totalPoints', total_points,
           'placement', placement, 'qualifies', placement <= 2
         ) order by placement, alias), '[]'::jsonb)
    from ranked;
$$;

revoke all on function public.room_standings_compute(uuid, uuid) from public;

-- ============================================================ 2. room_standings() — unchanged contract, now calls the helper

-- Identical authorization (require_event_admin(), staff only) and
-- identical return shape to the version this supersedes — the only
-- change is that the computation itself now lives in
-- room_standings_compute() instead of being duplicated inline.
create or replace function public.room_standings(p_room_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
declare
  v_event_id uuid;
begin
  select event_id into v_event_id from rooms where id = p_room_id;
  if v_event_id is null then
    raise exception 'room_not_found: no such room' using errcode = 'no_data_found';
  end if;
  perform public.require_event_admin();

  return public.room_standings_compute(p_room_id, v_event_id);
end;
$$;

-- ============================================================ 3. coordinator_room_standings() — the actual fix

-- Same computation, different (narrower) authorization: the existing
-- is_authorized_for_room() model — staff OR the room's own active
-- coordinator, never an unrelated player, never a different room's
-- coordinator. p_room_id is never trusted alone; is_authorized_for_room()
-- re-derives the caller's identity from auth.uid() server-side and
-- checks it against this exact room, the same discipline every
-- coordinator-facing function since Phase 8 has used.
create or replace function public.coordinator_room_standings(p_room_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
declare
  v_event_id uuid;
begin
  select event_id into v_event_id from rooms where id = p_room_id;
  if v_event_id is null then
    raise exception 'room_not_found: no such room' using errcode = 'no_data_found';
  end if;

  if not public.is_authorized_for_room(p_room_id) then
    raise exception 'not_authorized: not this room''s coordinator or an event admin' using errcode = '42501';
  end if;

  return public.room_standings_compute(p_room_id, v_event_id);
end;
$$;

revoke all on function public.coordinator_room_standings(uuid) from public;
grant execute on function public.coordinator_room_standings(uuid) to authenticated;
