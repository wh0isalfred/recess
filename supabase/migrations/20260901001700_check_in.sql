-- 0017 — check-in, sequential room assignment, and get_player_state(). Phase 5.
--
-- Two functions. get_player_state() is read-only and is the exact function
-- ARCHITECTURE.md §2 already names and specs — "one server function returns
-- the player's entire current state as a tagged union... the React app
-- renders whichever view comes back, it contains no rules about which
-- screen to show." check_in_player() is the one write this phase adds, and
-- it returns get_player_state() itself so the client never has to guess
-- what changed.
--
-- Scope: the doc's full view list is LANDING, REGISTRATION_CLOSED,
-- PASS_COUNTDOWN, CHECK_IN_OPEN, CHECKED_IN_WAITING, LATE_ARRIVAL,
-- ROOM_ASSIGNED, LIVE_ROUND, BETWEEN_GAMES, PAUSED, RESULTS. Screens 07-08
-- only need PASS_COUNTDOWN and CHECK_IN_OPEN, and the check-in transaction
-- itself produces CHECKED_IN_WAITING/ROOM_ASSIGNED as data facts even though
-- Screen 09 doesn't exist yet — this migration computes those two views
-- correctly (a checked-in player refreshing /pass must land somewhere true)
-- but the client (this phase) renders them with a minimal, undesigned
-- fallback rather than inventing Screen 09's art direction. LATE_ARRIVAL,
-- LIVE_ROUND, BETWEEN_GAMES, PAUSED and RESULTS need rounds/results data
-- this phase doesn't touch; get_player_state() tags a reasonable view for
-- LIVE/PAUSED/COMPLETE so the function stays honest for any event state,
-- but the payload for those is intentionally minimal — real support is
-- later work. WAITLISTED and EVENT_CANCELLED are two views this migration
-- adds beyond the doc's list, for the same reason WAITLISTED already exists
-- as a registration_status: the schema has the fact, so the function reports
-- it truthfully rather than crashing or mislabelling it as something else.
--
-- Deviation from the doc's literal signature: get_player_state() takes no
-- registration_id parameter and derives the caller's registration from
-- auth.uid() alone, the same way get_my_registration() already does. A
-- client-supplied registration_id is a parameter worth not trusting when
-- auth.uid() already disambiguates it correctly on its own.

-- ---------------------------------------------------------------- get_player_state

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

  select rm.id, rm2.label as room_label
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
      -- Never checked in but the event moved on without them. Not one of
      -- the doc's named views (LATE_ARRIVAL covers a related but different
      -- case — a room reassignment mid-game — and needs machinery this
      -- phase doesn't build); tagged plainly rather than mislabelled.
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
      -- The main group is only ever handed to the client on the view that
      -- is meant to show it — see the migration header on room privacy.
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

  -- 'room' is present only when a real membership exists — omitted
  -- entirely, not present-with-null, the same treatment 'games' gets below.
  -- A key that is simply absent is what "no room yet" should look like on
  -- the wire, and it is what a plain `state.room?.label` reads naturally
  -- from on the client.
  if v_membership.id is not null then
    v_payload := v_payload || jsonb_build_object(
      'room', jsonb_build_object('label', v_membership.room_label)
    );
  end if;

  if v_view = 'PASS_COUNTDOWN' then
    v_payload := v_payload || jsonb_build_object('games', (
      select coalesce(jsonb_agg(
               jsonb_build_object(
                 'slug', g.slug,
                 'name', coalesce(eg.display_name, g.name),
                 'platform', g.platform
               ) order by eg.position
             ), '[]'::jsonb)
        from public.event_games eg
        join public.games g on g.id = eg.game_id
       where eg.event_id = v_reg.event_id and g.status = 'ACTIVE'
    ));
  end if;

  return v_payload;
end;
$$;

revoke all on function public.get_player_state() from public;
grant execute on function public.get_player_state() to authenticated;

-- -------------------------------------------------------------------- check_in_player

create or replace function public.check_in_player()
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_uid           uuid;
  v_reg           record;
  v_event         record;
  v_room          record;
  v_membership_id uuid;
begin
  v_uid := auth.uid();
  if v_uid is null then
    raise exception 'not_authenticated: no player session' using errcode = '28000';
  end if;

  select r.* into v_reg
    from public.event_registrations r
   where r.auth_user_id = v_uid
   order by r.created_at desc
   limit 1;

  if not found then
    raise exception 'not_registered: no registration found for this session' using errcode = 'no_data_found';
  end if;

  if v_reg.status = 'WAITLISTED' then
    raise exception 'waitlisted: waitlisted registrations cannot check in' using errcode = '55000';
  end if;
  if v_reg.status = 'CANCELLED' then
    raise exception 'cancelled: this registration was cancelled' using errcode = '55000';
  end if;

  select * into v_event from public.events where id = v_reg.event_id;

  if v_event.status <> 'CHECK_IN' then
    raise exception 'check_in_not_open: check-in is not open right now' using errcode = '55000';
  end if;
  if v_event.checkin_opens_at is not null and now() < v_event.checkin_opens_at then
    raise exception 'check_in_not_open: check-in has not opened yet' using errcode = '55000';
  end if;
  if v_event.checkin_closes_at is not null and now() >= v_event.checkin_closes_at then
    raise exception 'check_in_closed: check-in has closed' using errcode = '55000';
  end if;

  -- Idempotent: already checked in (a page reload, a resubmitted tap that
  -- actually landed) just returns the current state rather than erroring
  -- or re-running assignment a second time.
  if v_reg.checked_in_at is not null then
    return public.get_player_state();
  end if;

  update public.event_registrations
     set checked_in_at = now()
   where id = v_reg.id and checked_in_at is null;

  -- The WHERE guard means a genuine double-tap race resolves here: whichever
  -- call's UPDATE commits first wins it; the second affects zero rows,
  -- finds `not found`, and falls through to the same idempotent return
  -- above rather than double-assigning a room.
  if not found then
    return public.get_player_state();
  end if;

  -- Sequential fill, position ascending, first room with headroom. Locking
  -- every room row for this event up front — not just the one we end up
  -- using — is what actually serializes concurrent check-ins: a second
  -- transaction's own attempt to lock the same rooms blocks until this one
  -- commits, so two people racing for the last seat cannot both take it.
  -- SKIP LOCKED was considered and rejected: it would let two concurrent
  -- transactions grab different rooms without waiting, which is faster but
  -- can violate strict fill-by-position under contention — the wrong trade
  -- for "never exceed capacity" and "check-in order determines priority."
  for v_room in
    select rm.* from public.rooms rm
     where rm.event_id = v_reg.event_id
     order by rm.position
     for update
  loop
    -- A room with no configured capacity is not assignable, never
    -- unlimited — see rooms.capacity's own comment in migration 0007.
    if v_room.capacity is null then
      continue;
    end if;

    if (
      select count(*) from public.room_memberships
       where room_id = v_room.id and left_at is null
    ) < v_room.capacity then
      insert into public.room_memberships (event_id, room_id, registration_id)
      values (v_reg.event_id, v_room.id, v_reg.id)
      returning id into v_membership_id;
      exit;
    end if;
  end loop;

  -- v_membership_id stays null when every room is full. That is
  -- WAITING_FOR_ROOM: a checked-in registration with no active membership,
  -- not an error and not a separate boolean column.

  insert into public.audit_logs (event_id, actor_user_id, action, entity_type, entity_id, after)
  values (
    v_reg.event_id, v_uid, 'registration.checked_in', 'event_registrations', v_reg.id,
    jsonb_build_object('checked_in_at', now(), 'room_membership_id', v_membership_id)
  );

  return public.get_player_state();
end;
$$;

revoke all on function public.check_in_player() from public;
grant execute on function public.check_in_player() to authenticated;
