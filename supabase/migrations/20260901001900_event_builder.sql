-- 0019 — the Event Builder. Phase 7.
--
-- The gap this closes: every event so far, including recess-01, exists
-- because someone hand-wrote an INSERT into seed.sql. There has been no way
-- to create a real event from the product. This migration adds exactly the
-- write surface the admin Event Builder needs and nothing about the
-- lifecycle itself — creating an event still lands it at DRAFT (the
-- table's own default), and DRAFT -> REGISTRATION still runs through
-- transition_event() (0012) with its existing preconditions (a registration
-- window, at least one game) unchanged. This migration adds no new lifecycle
-- rule; it only gives admin a way to reach the state transition_event()
-- already requires before it will move an event out of DRAFT.
--
-- Five functions: admin_create_event, admin_list_events, admin_get_event
-- (the detail a builder review step or an "open existing event" page needs),
-- admin_list_games (the Game Library picker), admin_add_event_game. Room
-- creation reuses admin_upsert_room (0018) unchanged — a room is a room
-- regardless of which screen created it, and duplicating that function here
-- was exactly the kind of thing this phase was told not to do.

create or replace function public.admin_create_event(
  p_slug                   text,
  p_name                   text,
  p_starts_at              timestamptz,
  p_timezone               text,
  p_timezone_label         text,
  p_registration_opens_at  timestamptz,
  p_registration_closes_at timestamptz,
  p_checkin_opens_at       timestamptz,
  p_checkin_closes_at      timestamptz,
  p_capacity               integer,
  p_whatsapp_group_url     text
) returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_uid uuid := auth.uid();
  v_event public.events;
begin
  perform public.require_event_admin();

  if btrim(coalesce(p_name, '')) = '' then
    raise exception 'invalid_name: event name is required' using errcode = '22023';
  end if;
  if btrim(coalesce(p_slug, '')) = '' then
    raise exception 'invalid_slug: event slug is required' using errcode = '22023';
  end if;
  if p_capacity is null or p_capacity <= 0 then
    raise exception 'invalid_capacity: capacity must be a positive number' using errcode = '22023';
  end if;
  if p_whatsapp_group_url is not null and not public.is_whatsapp_group_url(p_whatsapp_group_url) then
    raise exception 'invalid_whatsapp_url: not a WhatsApp group invite link' using errcode = '22023';
  end if;

  begin
    insert into public.events (
      slug, name, starts_at, timezone, timezone_label,
      registration_opens_at, registration_closes_at,
      checkin_opens_at, checkin_closes_at,
      capacity, whatsapp_group_url, created_by
    ) values (
      lower(btrim(p_slug)), btrim(p_name), p_starts_at, p_timezone, p_timezone_label,
      p_registration_opens_at, p_registration_closes_at,
      p_checkin_opens_at, p_checkin_closes_at,
      p_capacity, p_whatsapp_group_url, v_uid
    ) returning * into v_event;
  exception
    when unique_violation then
      raise exception 'slug_taken: an event with that slug already exists' using errcode = '23505';
    when check_violation then
      -- Covers every other events_* check constraint (slug format, window
      -- ordering, whatsapp shape) with the same shape of message the rest
      -- of this migration set already uses, rather than a raw constraint name.
      raise exception 'invalid_event: check the event details and try again' using errcode = '22023';
  end;

  insert into audit_logs (event_id, actor_user_id, action, entity_type, entity_id, after)
  values (v_event.id, v_uid, 'event.created', 'events', v_event.id,
          jsonb_build_object('slug', v_event.slug, 'name', v_event.name));

  return jsonb_build_object('id', v_event.id, 'slug', v_event.slug, 'status', v_event.status);
end;
$$;

create or replace function public.admin_list_events()
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
             'slug', e.slug, 'name', e.name, 'status', e.status,
             'startsAt', e.starts_at, 'timezone', e.timezone, 'timezoneLabel', e.timezone_label,
             'registeredCount', (select count(*) from event_registrations where event_id = e.id and status in ('REGISTERED','WAITLISTED'))
           ) order by e.starts_at desc), '[]'::jsonb)
      from events e
  );
end;
$$;

create or replace function public.admin_get_event(p_event_slug text)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
declare
  v_event record;
begin
  perform public.require_event_admin();

  select * into v_event from events where slug = p_event_slug;
  if not found then
    raise exception 'event_not_found: no such event' using errcode = 'no_data_found';
  end if;

  return jsonb_build_object(
    'slug', v_event.slug, 'name', v_event.name, 'status', v_event.status,
    'startsAt', v_event.starts_at, 'timezone', v_event.timezone, 'timezoneLabel', v_event.timezone_label,
    'registrationOpensAt', v_event.registration_opens_at, 'registrationClosesAt', v_event.registration_closes_at,
    'checkinOpensAt', v_event.checkin_opens_at, 'checkinClosesAt', v_event.checkin_closes_at,
    'capacity', v_event.capacity, 'whatsappGroupUrl', v_event.whatsapp_group_url,
    'games', (
      select coalesce(jsonb_agg(jsonb_build_object(
               'eventGameId', eg.id, 'gameId', g.id, 'slug', g.slug,
               'name', coalesce(eg.display_name, g.name), 'position', eg.position
             ) order by eg.position), '[]'::jsonb)
        from event_games eg join games g on g.id = eg.game_id
       where eg.event_id = v_event.id
    ),
    'rooms', (
      select coalesce(jsonb_agg(jsonb_build_object(
               'id', ro.id, 'label', ro.label, 'position', ro.position, 'capacity', ro.capacity
             ) order by ro.position), '[]'::jsonb)
        from rooms ro where ro.event_id = v_event.id
    )
  );
end;
$$;

create or replace function public.admin_list_games()
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
             'id', g.id, 'slug', g.slug, 'name', g.name, 'platform', g.platform,
             'scoringTemplate', g.scoring_template, 'defaultRoundCount', g.default_round_count
           ) order by g.name), '[]'::jsonb)
      from games g where g.status = 'ACTIVE'
  );
end;
$$;

-- Position is caller-supplied (the builder controls game order directly,
-- the same way room order is caller-supplied in admin_upsert_room) rather
-- than auto-incrementing, so the whole ordered list can be written in one
-- pass without a read-modify-write race between games in the same request.
create or replace function public.admin_add_event_game(
  p_event_slug text,
  p_game_id    uuid,
  p_position   integer
) returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_uid uuid := auth.uid();
  v_event_id uuid;
  v_game record;
  v_event_game public.event_games;
begin
  perform public.require_event_admin();

  select id into v_event_id from events where slug = p_event_slug;
  if not found then
    raise exception 'event_not_found: no such event' using errcode = 'no_data_found';
  end if;

  select * into v_game from games where id = p_game_id and status = 'ACTIVE';
  if not found then
    raise exception 'game_not_found: no such game in the library' using errcode = 'no_data_found';
  end if;

  if p_position is null or p_position <= 0 then
    raise exception 'invalid_position: position must be a positive number' using errcode = '22023';
  end if;

  -- event_games_position_key is deferrable (position reordering elsewhere
  -- in the schema needs that), and Postgres does not allow ON CONFLICT to
  -- target a deferrable constraint at all — so this is a plain insert, not
  -- an upsert. (event_id, game_id) staying unique is what the exception
  -- handler below actually guards against; a genuine position collision
  -- within one builder session doesn't arise since positions are assigned
  -- in order by the caller.
  begin
    insert into event_games (event_id, game_id, position, scoring_template, planned_rounds)
    values (v_event_id, v_game.id, p_position, v_game.scoring_template, v_game.default_round_count)
    returning * into v_event_game;
  exception
    when unique_violation then
      raise exception 'game_already_added: this game is already in the event' using errcode = '23505';
  end;

  insert into audit_logs (event_id, actor_user_id, action, entity_type, entity_id, after)
  values (v_event_id, v_uid, 'event_game.added', 'event_games', v_event_game.id,
          jsonb_build_object('gameSlug', v_game.slug, 'position', p_position));

  return jsonb_build_object('id', v_event_game.id, 'gameSlug', v_game.slug, 'position', p_position);
end;
$$;

revoke all on function public.admin_create_event(text, text, timestamptz, text, text, timestamptz, timestamptz, timestamptz, timestamptz, integer, text) from public;
revoke all on function public.admin_list_events() from public;
revoke all on function public.admin_get_event(text) from public;
revoke all on function public.admin_list_games() from public;
revoke all on function public.admin_add_event_game(text, uuid, integer) from public;

grant execute on function public.admin_create_event(text, text, timestamptz, text, text, timestamptz, timestamptz, timestamptz, timestamptz, integer, text) to authenticated;
grant execute on function public.admin_list_events() to authenticated;
grant execute on function public.admin_get_event(text) to authenticated;
grant execute on function public.admin_list_games() to authenticated;
grant execute on function public.admin_add_event_game(text, uuid, integer) to authenticated;

-- ------------------------------------------------------------- admin_open_registration

-- Same shape as admin_open_check_in() (0018): transition_event() (0012)
-- deliberately performs no authorization check of its own — "Role
-- authorization... is deliberately NOT implemented here" is the migration's
-- own comment — so calling it directly from the browser's RPC surface would
-- let any authenticated session, staff or not, move an event to
-- REGISTRATION. This wrapper is what actually gates it.
create or replace function public.admin_open_registration(p_event_slug text)
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

  perform public.transition_event(v_event_id, 'REGISTRATION');

  return jsonb_build_object('eventId', v_event_id, 'status', 'REGISTRATION');
end;
$$;

revoke all on function public.admin_open_registration(text) from public;
grant execute on function public.admin_open_registration(text) to authenticated;
