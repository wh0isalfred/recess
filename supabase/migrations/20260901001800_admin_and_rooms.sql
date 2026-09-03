-- 0018 — game artwork, Screen 09's real payload, and the first admin slice.
-- Phase 6.
--
-- Four independent pieces, in order:
--   1. games.artwork_url — card-sized artwork, alongside the existing
--      icon_url rather than replacing it (see the column's own comment).
--   2. get_player_state() extended: ROOM_ASSIGNED now carries the room's
--      real capacity/occupancy/WhatsApp link, the roommate roster (aliases
--      only), and the up-first game — still SECURITY DEFINER, still no RLS
--      policy, same shape as 0016/0017.
--   3. A staff-authorization helper, and five admin RPCs built on it —
--      the first callers of it that exist.
--   4. admin_assign_waiting_players() — the same sequential-fill shape as
--      check_in_player() in 0017, reused for the operator-triggered case.
--
-- Storage decision: every other piece of RECESS artwork (die, pawn, knight,
-- rook) already ships as a static file under public/brand/. Game artwork
-- gets the same treatment — public/games/<slug>.webp, no Supabase Storage
-- bucket — because these are three known, checked-in images the app ships
-- with, not admin-uploaded content. artwork_url is constrained to a
-- same-origin relative path for exactly the reason the brief names: an
-- external URL handed to next/image is an open redirect/SSRF-shaped risk
-- this schema has no reason to accept yet.

-- ------------------------------------------------------------------- artwork

alter table public.games add column artwork_url text;

comment on column public.games.icon_url is
  'Small inline icon (a list row, a chip). Unused so far — kept for that case.';
comment on column public.games.artwork_url is
  'Card-sized artwork (Screen 07 GET READY, Screen 09 UP FIRST, admin). Same
   same-origin-path rule as icon_url once that is populated.';

alter table public.games add constraint games_artwork_url_same_origin
  check (artwork_url is null or artwork_url ~ '^/[A-Za-z0-9/_.-]+\.(webp|png|jpg|jpeg|svg)$');
alter table public.games add constraint games_icon_url_same_origin
  check (icon_url is null or icon_url ~ '^/[A-Za-z0-9/_.-]+\.(webp|png|jpg|jpeg|svg)$');

update public.games set artwork_url = '/games/' || slug || '.webp';

-- --------------------------------------------------------------- get_player_state

create or replace function public.get_player_state()
returns jsonb
language plpgsql
security definer
stable
set search_path = public, pg_temp
as $$
declare
  v_uid       uuid;
  v_reg       record;
  v_membership record;
  v_view      text;
  v_checkin_available boolean;
  v_payload   jsonb;
  v_up_first  jsonb;
begin
  v_uid := auth.uid();
  if v_uid is null then
    return null;
  end if;

  select r.id, r.alias, r.player_number, r.status, r.checked_in_at, r.event_id,
         e.slug as event_slug, e.name as event_name, e.status as event_status,
         e.starts_at, e.timezone, e.timezone_label, e.whatsapp_group_url,
         e.checkin_opens_at, e.checkin_closes_at
    into v_reg
    from public.event_registrations r
    join public.events e on e.id = r.event_id
   where r.auth_user_id = v_uid
   order by r.created_at desc
   limit 1;

  if not found then
    return null;
  end if;

  select rm.id, rm.room_id, rm2.label as room_label, rm2.capacity as room_capacity,
         rm2.whatsapp_group_url as room_whatsapp_url
    into v_membership
    from public.room_memberships rm
    join public.rooms rm2 on rm2.id = rm.room_id
   where rm.registration_id = v_reg.id and rm.left_at is null;

  v_checkin_available :=
    (v_reg.checkin_opens_at is null or now() >= v_reg.checkin_opens_at)
    and (v_reg.checkin_closes_at is null or now() < v_reg.checkin_closes_at);

  if v_reg.status = 'CANCELLED' then
    v_view := 'CANCELLED';
  elsif v_reg.status = 'WAITLISTED' then
    v_view := 'WAITLISTED';
  elsif v_reg.event_status = 'CANCELLED' then
    v_view := 'EVENT_CANCELLED';
  elsif v_reg.event_status in ('DRAFT', 'REGISTRATION', 'REGISTRATION_CLOSED') then
    v_view := 'PASS_COUNTDOWN';
  elsif v_reg.event_status = 'CHECK_IN' then
    if v_reg.checked_in_at is null then
      v_view := 'CHECK_IN_OPEN';
    elsif v_membership.id is not null then
      v_view := 'ROOM_ASSIGNED';
    else
      v_view := 'CHECKED_IN_WAITING';
    end if;
  elsif v_reg.event_status in ('LIVE', 'PAUSED') then
    if v_reg.checked_in_at is null then
      v_view := 'MISSED_CHECK_IN';
    elsif v_membership.id is not null then
      v_view := 'ROOM_ASSIGNED';
    else
      v_view := 'CHECKED_IN_WAITING';
    end if;
  else
    v_view := 'RESULTS';
  end if;

  v_payload := jsonb_build_object(
    'view', v_view,
    'event', jsonb_build_object(
      'slug', v_reg.event_slug,
      'name', v_reg.event_name,
      'status', v_reg.event_status,
      'startsAt', v_reg.starts_at,
      'timezone', v_reg.timezone,
      'timezoneLabel', v_reg.timezone_label,
      'whatsappGroupUrl', case when v_view = 'PASS_COUNTDOWN' then v_reg.whatsapp_group_url else null end
    ),
    'player', jsonb_build_object(
      'alias', v_reg.alias,
      'number', v_reg.player_number,
      'registrationStatus', v_reg.status,
      'checkedInAt', v_reg.checked_in_at
    ),
    'checkIn', jsonb_build_object(
      'opensAt', v_reg.checkin_opens_at,
      'closesAt', v_reg.checkin_closes_at,
      'available', v_checkin_available
    )
  );

  if v_view = 'PASS_COUNTDOWN' then
    v_payload := v_payload || jsonb_build_object('games', (
      select coalesce(jsonb_agg(
               jsonb_build_object(
                 'slug', g.slug,
                 'name', coalesce(eg.display_name, g.name),
                 'platform', g.platform,
                 'artworkUrl', g.artwork_url,
                 'iconUrl', g.icon_url
               ) order by eg.position
             ), '[]'::jsonb)
        from public.event_games eg
        join public.games g on g.id = eg.game_id
       where eg.event_id = v_reg.event_id and g.status = 'ACTIVE'
    ));
  end if;

  -- ROOM_ASSIGNED: the real Screen 09 payload. Roster is aliases only, no
  -- registration id, no phone, no player_number beyond the caller's own —
  -- the same room's roommates are not this player's business to number.
  if v_view = 'ROOM_ASSIGNED' then
    select jsonb_build_object(
             'slug', g.slug, 'name', g.name, 'platform', g.platform,
             'artworkUrl', g.artwork_url, 'iconUrl', g.icon_url
           )
      into v_up_first
      from public.event_games eg
      join public.games g on g.id = eg.game_id
     where eg.event_id = v_reg.event_id and g.status = 'ACTIVE'
     order by eg.position
     limit 1;

    v_payload := v_payload || jsonb_build_object(
      'room', jsonb_build_object(
        'label', v_membership.room_label,
        'capacity', v_membership.room_capacity,
        'occupancy', (
          select count(*) from public.room_memberships
           where room_id = v_membership.room_id and left_at is null
        ),
        'whatsappGroupUrl', v_membership.room_whatsapp_url,
        'roster', (
          select coalesce(jsonb_agg(jsonb_build_object('alias', er.alias) order by rm.assigned_at), '[]'::jsonb)
            from public.room_memberships rm
            join public.event_registrations er on er.id = rm.registration_id
           where rm.room_id = v_membership.room_id and rm.left_at is null
        )
      ),
      'upFirstGame', v_up_first
    );
  end if;

  return v_payload;
end;
$$;

-- ----------------------------------------------------------------- staff auth

-- The one helper every admin RPC below gates on. Not exposed to PostgREST —
-- called from inside other SECURITY DEFINER functions only.
create or replace function public.current_staff_role()
returns public.staff_role
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select role from public.staff_profiles where user_id = auth.uid();
$$;

create or replace function public.require_event_admin()
returns void
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
begin
  -- COORDINATOR is a real, existing role — deliberately not admitted here.
  -- Room/event CRUD is EVENT_ADMIN and SUPER_ADMIN only; giving coordinators
  -- these rights because coordinator_assignments happens to exist would be
  -- exactly the accidental escalation the brief calls out.
  --
  -- The explicit IS NULL check matters: `null not in (...)` evaluates to
  -- null, not true, so a bare `if ... not in (...)` silently lets through
  -- anyone with no staff_profiles row at all — every ordinary player. Caught
  -- by test 40 before this ever ran anywhere real.
  if public.current_staff_role() is null
     or public.current_staff_role() not in ('SUPER_ADMIN', 'EVENT_ADMIN') then
    raise exception 'not_authorized: staff access required' using errcode = '42501';
  end if;
end;
$$;

revoke all on function public.current_staff_role() from public;
revoke all on function public.require_event_admin() from public;

-- The one staff-facing read PostgREST actually needs: "who am I, as staff."
-- Scoped to auth.uid() exactly like get_my_registration() always was — a
-- staff member reading their own profile is not an admin operation and
-- does not gate on require_event_admin().
create or replace function public.get_my_staff_profile()
returns jsonb
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select jsonb_build_object('name', name, 'role', role)
    from public.staff_profiles
   where user_id = auth.uid();
$$;

revoke all on function public.get_my_staff_profile() from public;
grant execute on function public.get_my_staff_profile() to authenticated;

-- --------------------------------------------------------- admin_event_overview

create or replace function public.admin_event_overview(p_event_slug text)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
declare
  v_event record;
  v_result jsonb;
begin
  perform public.require_event_admin();

  select * into v_event from public.events where slug = p_event_slug;
  if not found then
    raise exception 'event_not_found: no such event' using errcode = 'no_data_found';
  end if;

  select jsonb_build_object(
    'event', jsonb_build_object(
      'slug', v_event.slug, 'name', v_event.name, 'status', v_event.status,
      'startsAt', v_event.starts_at, 'timezone', v_event.timezone, 'timezoneLabel', v_event.timezone_label,
      'capacity', v_event.capacity
    ),
    'counts', jsonb_build_object(
      'registered', (select count(*) from event_registrations where event_id = v_event.id and status in ('REGISTERED','WAITLISTED')),
      'checkedIn', (select count(*) from event_registrations where event_id = v_event.id and checked_in_at is not null),
      'assigned', (select count(*) from room_memberships rm join event_registrations er on er.id = rm.registration_id
                    where er.event_id = v_event.id and rm.left_at is null),
      'waiting', (select count(*) from event_registrations er
                   where er.event_id = v_event.id and er.checked_in_at is not null
                     and not exists (select 1 from room_memberships rm where rm.registration_id = er.id and rm.left_at is null))
    ),
    'rooms', (
      select coalesce(jsonb_agg(jsonb_build_object(
               'id', ro.id, 'label', ro.label, 'position', ro.position, 'capacity', ro.capacity,
               'occupancy', (select count(*) from room_memberships where room_id = ro.id and left_at is null)
             ) order by ro.position), '[]'::jsonb)
        from rooms ro where ro.event_id = v_event.id
    ),
    'nextGame', (
      select jsonb_build_object('slug', g.slug, 'name', coalesce(eg.display_name, g.name), 'roundCount', g.default_round_count)
        from event_games eg join games g on g.id = eg.game_id
       where eg.event_id = v_event.id and g.status = 'ACTIVE'
       order by eg.position limit 1
    )
  ) into v_result;

  return v_result;
end;
$$;

-- -------------------------------------------------------------- admin_list_rooms

create or replace function public.admin_list_rooms(p_event_slug text)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
declare
  v_event_id uuid;
  v_result jsonb;
begin
  perform public.require_event_admin();

  select id into v_event_id from events where slug = p_event_slug;
  if not found then
    raise exception 'event_not_found: no such event' using errcode = 'no_data_found';
  end if;

  select jsonb_build_object(
    'rooms', (
      select coalesce(jsonb_agg(jsonb_build_object(
               'id', ro.id, 'label', ro.label, 'position', ro.position, 'capacity', ro.capacity,
               'whatsappGroupUrl', ro.whatsapp_group_url,
               'occupancy', (select count(*) from room_memberships where room_id = ro.id and left_at is null),
               'coordinator', (
                 select jsonb_build_object('userId', sp.user_id, 'name', sp.name)
                   from coordinator_assignments ca join staff_profiles sp on sp.user_id = ca.user_id
                  where ca.event_id = v_event_id and ca.room_id = ro.id
                  limit 1
               )
             ) order by ro.position), '[]'::jsonb)
        from rooms ro where ro.event_id = v_event_id
    ),
    'waiting', (
      select coalesce(jsonb_agg(jsonb_build_object(
               'alias', er.alias, 'playerNumber', er.player_number, 'checkedInAt', er.checked_in_at
             ) order by er.checked_in_at), '[]'::jsonb)
        from event_registrations er
       where er.event_id = v_event_id and er.checked_in_at is not null
         and not exists (select 1 from room_memberships rm where rm.registration_id = er.id and rm.left_at is null)
    )
  ) into v_result;

  return v_result;
end;
$$;

-- -------------------------------------------------------------- admin_upsert_room

create or replace function public.admin_upsert_room(
  p_event_slug text,
  p_room_id    uuid,
  p_label      text,
  p_capacity   integer,
  p_whatsapp_group_url text
) returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_uid uuid := auth.uid();
  v_event_id uuid;
  v_room record;
  v_next_position integer;
begin
  perform public.require_event_admin();

  select id into v_event_id from events where slug = p_event_slug;
  if not found then
    raise exception 'event_not_found: no such event' using errcode = 'no_data_found';
  end if;

  if btrim(coalesce(p_label, '')) = '' then
    raise exception 'invalid_label: room label is required' using errcode = '22023';
  end if;
  if p_capacity is not null and p_capacity <= 0 then
    raise exception 'invalid_capacity: capacity must be a positive number' using errcode = '22023';
  end if;
  if p_whatsapp_group_url is not null and not public.is_whatsapp_group_url(p_whatsapp_group_url) then
    raise exception 'invalid_whatsapp_url: not a WhatsApp group invite link' using errcode = '22023';
  end if;

  if p_room_id is null then
    select coalesce(max(position), 0) + 1 into v_next_position from rooms where event_id = v_event_id;

    insert into rooms (event_id, label, position, capacity, whatsapp_group_url)
    values (v_event_id, btrim(p_label), v_next_position, p_capacity, p_whatsapp_group_url)
    returning * into v_room;

    insert into audit_logs (event_id, actor_user_id, action, entity_type, entity_id, after)
    values (v_event_id, v_uid, 'room.created', 'rooms', v_room.id,
            jsonb_build_object('label', v_room.label, 'capacity', v_room.capacity));
  else
    select * into v_room from rooms where id = p_room_id and event_id = v_event_id;
    if not found then
      raise exception 'room_not_found: no such room on this event' using errcode = 'no_data_found';
    end if;

    update rooms
       set label = btrim(p_label), capacity = p_capacity, whatsapp_group_url = p_whatsapp_group_url
     where id = p_room_id
     returning * into v_room;

    insert into audit_logs (event_id, actor_user_id, action, entity_type, entity_id, before, after)
    values (v_event_id, v_uid, 'room.updated', 'rooms', v_room.id,
            jsonb_build_object('label', v_room.label),
            jsonb_build_object('label', v_room.label, 'capacity', v_room.capacity, 'whatsapp', v_room.whatsapp_group_url is not null));
  end if;

  return jsonb_build_object('id', v_room.id, 'label', v_room.label, 'position', v_room.position,
                             'capacity', v_room.capacity, 'whatsappGroupUrl', v_room.whatsapp_group_url);
end;
$$;

-- --------------------------------------------------------- admin_assign_coordinator

create or replace function public.admin_assign_coordinator(
  p_event_slug text,
  p_room_id    uuid,
  p_user_id    uuid
) returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_uid uuid := auth.uid();
  v_event_id uuid;
begin
  perform public.require_event_admin();

  select id into v_event_id from events where slug = p_event_slug;
  if not found then
    raise exception 'event_not_found: no such event' using errcode = 'no_data_found';
  end if;

  if not exists (select 1 from rooms where id = p_room_id and event_id = v_event_id) then
    raise exception 'room_not_found: no such room on this event' using errcode = 'no_data_found';
  end if;

  -- V1 keeps this to one coordinator per room: clear any existing
  -- assignment for the room before writing the new one, rather than
  -- accumulating a history the product has no use for yet.
  delete from coordinator_assignments where event_id = v_event_id and room_id = p_room_id;

  if p_user_id is not null then
    if public.current_staff_role() is null then
      raise exception 'invalid_staff: target user is not a staff member' using errcode = '22023';
    end if;

    insert into coordinator_assignments (event_id, user_id, room_id)
    values (v_event_id, p_user_id, p_room_id);
  end if;

  insert into audit_logs (event_id, actor_user_id, action, entity_type, entity_id, after)
  values (v_event_id, v_uid, 'room.coordinator_assigned', 'rooms', p_room_id,
          jsonb_build_object('coordinatorUserId', p_user_id));

  return jsonb_build_object('roomId', p_room_id, 'coordinatorUserId', p_user_id);
end;
$$;

-- ------------------------------------------------------------- admin_room_members

create or replace function public.admin_room_members(p_room_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
begin
  perform public.require_event_admin();

  return (
    select coalesce(jsonb_agg(jsonb_build_object(
             'alias', er.alias, 'playerNumber', er.player_number, 'assignedAt', rm.assigned_at
           ) order by rm.assigned_at), '[]'::jsonb)
      from room_memberships rm
      join event_registrations er on er.id = rm.registration_id
     where rm.room_id = p_room_id and rm.left_at is null
  );
end;
$$;

-- --------------------------------------------------------- assign waiting players

create or replace function public.admin_assign_waiting_players(p_event_slug text)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_uid uuid := auth.uid();
  v_event record;
  v_reg record;
  v_room record;
  v_membership_id uuid;
  v_assigned int := 0;
  v_still_waiting int := 0;
begin
  perform public.require_event_admin();

  select * into v_event from events where slug = p_event_slug;
  if not found then
    raise exception 'event_not_found: no such event' using errcode = 'no_data_found';
  end if;

  -- Same lock as check_in_player(): every room row for the event, held for
  -- the whole operation, so this cannot race a player's own concurrent
  -- check-in (which takes the identical lock) into overfilling a room.
  for v_reg in
    select er.* from event_registrations er
     where er.event_id = v_event.id and er.checked_in_at is not null
       and not exists (select 1 from room_memberships rm where rm.registration_id = er.id and rm.left_at is null)
     order by er.checked_in_at
  loop
    v_membership_id := null;

    for v_room in
      select ro.* from rooms ro where ro.event_id = v_event.id order by ro.position for update
    loop
      if v_room.capacity is null then
        continue;
      end if;
      if (select count(*) from room_memberships where room_id = v_room.id and left_at is null) < v_room.capacity then
        insert into room_memberships (event_id, room_id, registration_id)
        values (v_event.id, v_room.id, v_reg.id)
        returning id into v_membership_id;
        exit;
      end if;
    end loop;

    if v_membership_id is not null then
      v_assigned := v_assigned + 1;
    else
      v_still_waiting := v_still_waiting + 1;
      -- Every remaining room is full for this pass — later waiting
      -- registrations will not find room either, so stop scanning them.
      exit;
    end if;
  end loop;

  insert into audit_logs (event_id, actor_user_id, action, entity_type, after)
  values (v_event.id, v_uid, 'room.waiting_assigned', 'events',
          jsonb_build_object('assigned', v_assigned, 'stillWaiting', v_still_waiting));

  return jsonb_build_object('assigned', v_assigned, 'stillWaiting', v_still_waiting);
end;
$$;

revoke all on function public.admin_event_overview(text) from public;
revoke all on function public.admin_list_rooms(text) from public;
revoke all on function public.admin_upsert_room(text, uuid, text, integer, text) from public;
revoke all on function public.admin_assign_coordinator(text, uuid, uuid) from public;
revoke all on function public.admin_room_members(uuid) from public;
revoke all on function public.admin_assign_waiting_players(text) from public;

grant execute on function public.admin_event_overview(text) to authenticated;
grant execute on function public.admin_list_rooms(text) to authenticated;
grant execute on function public.admin_upsert_room(text, uuid, text, integer, text) to authenticated;
grant execute on function public.admin_assign_coordinator(text, uuid, uuid) to authenticated;
grant execute on function public.admin_room_members(uuid) to authenticated;
grant execute on function public.admin_assign_waiting_players(text) to authenticated;

-- ------------------------------------------------------------------ admin_open_check_in

-- The browser's Supabase client carries only the anon key + the staff
-- member's JWT — RLS (0013) has zero policies on `events`, so a raw
-- `select ... from events` from that client returns nothing regardless of
-- role. Every admin read/write goes through an RPC for exactly this reason;
-- this one resolves the event id itself and calls transition_event()
-- (0012) rather than duplicating its legality rules, per the brief.
create or replace function public.admin_open_check_in(p_event_slug text)
returns jsonb
language plpgsql
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

  perform public.transition_event(v_event_id, 'CHECK_IN');

  return jsonb_build_object('eventId', v_event_id, 'status', 'CHECK_IN');
end;
$$;

revoke all on function public.admin_open_check_in(text) from public;
grant execute on function public.admin_open_check_in(text) to authenticated;
