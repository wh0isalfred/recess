-- 0029 — Phase 8: Coordinator Experience backend support.
--
-- Two additions, no scoring-engine redesign:
--
--   1. get_player_state() gains a `coordinating` field — the existing
--      normal player-session function every screen already resolves
--      through (ARCHITECTURE.md §2). "The backend already recognizes an
--      active coordinator through their room assignment and normal
--      authenticated player registration" — this is that recognition,
--      surfaced to the client that already calls this function. It is a
--      UI signal only (whether to show an entry point to /coordinate) —
--      every actual coordinator action still independently enforces
--      is_authorized_for_room() server-side, same as before this
--      migration.
--
--   2. coordinator_room_state(p_room_id) — the one new read the
--      Coordinator Home screen needs: room/roster, current game, current
--      round, and enough of event_games' configuration (planned rounds,
--      duration, scoring_config) to render "Round 2 of 3, 18:42
--      remaining" without the client reconstructing any of that from
--      several separate calls. Everything else Phase 8 needs
--      (start_room_game, start_round, preview_round_result,
--      submit_round_result, complete_room_game, request_result_correction,
--      room_standings) already exists and is reused as-is.

-- ============================================================ 1. get_player_state()

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
  v_avatar_color text;
  v_social    jsonb;
  v_coordinating jsonb;
begin
  v_uid := auth.uid();
  if v_uid is null then
    return null;
  end if;

  select r.id, r.alias, r.player_number, r.status, r.checked_in_at, r.event_id,
         e.slug as event_slug, e.name as event_name, e.status as event_status,
         e.starts_at, e.timezone, e.timezone_label, e.whatsapp_group_url,
         e.checkin_opens_at, e.checkin_closes_at, p.avatar_color
    into v_reg
    from public.event_registrations r
    join public.events e on e.id = r.event_id
    join public.players p on p.id = r.player_id
   where r.auth_user_id = v_uid
   order by r.created_at desc
   limit 1;

  if not found then
    return null;
  end if;

  v_avatar_color := v_reg.avatar_color;

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

  -- Coordinator detection: an active (replaced_at is null) room_coordinators
  -- row for this registration, regardless of `view` — a coordinator is
  -- still a normal player first (EVENT-OPS.md §1), so this is additive
  -- information, not a different view/routing decision.
  select jsonb_build_object('roomId', rc.room_id, 'roomLabel', ro.label)
    into v_coordinating
    from public.room_coordinators rc
    join public.rooms ro on ro.id = rc.room_id
   where rc.registration_id = v_reg.id and rc.replaced_at is null;

  v_payload := jsonb_build_object(
    'view', v_view,
    'event', jsonb_build_object(
      'id', v_reg.event_id,
      'slug', v_reg.event_slug,
      'name', v_reg.event_name,
      'status', v_reg.event_status,
      'startsAt', v_reg.starts_at,
      'timezone', v_reg.timezone,
      'timezoneLabel', v_reg.timezone_label,
      'whatsappGroupUrl', case when v_view = 'PASS_COUNTDOWN' then v_reg.whatsapp_group_url else null end
    ),
    'player', jsonb_build_object(
      'registrationId', v_reg.id,
      'alias', v_reg.alias,
      'number', v_reg.player_number,
      'registrationStatus', v_reg.status,
      'checkedInAt', v_reg.checked_in_at,
      'avatarColor', v_avatar_color
    ),
    'checkIn', jsonb_build_object(
      'opensAt', v_reg.checkin_opens_at,
      'closesAt', v_reg.checkin_closes_at,
      'available', v_checkin_available
    ),
    'coordinating', v_coordinating
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

    -- Social proof: admitted (REGISTERED, not WAITLISTED) players only,
    -- ordered by player_number — guaranteed strictly increasing per event
    -- (allocated under the same locked counter check_in_player() already
    -- relies on), so ordering never ties the way created_at can when two
    -- registrations land in the same transaction/millisecond. alias +
    -- avatarColor only — never player_id, registration_id, phone, or
    -- real_name. avatars capped at 6 for the stack; previewAliases capped
    -- at 3 for the "kemz, sarahh, theomz + N others" text — the client
    -- computes the remainder from admittedCount, not from array length, so
    -- it stays correct even though only 6 avatars/3 aliases ever come down
    -- the wire.
    select jsonb_build_object(
             'admittedCount', (
               select count(*) from public.event_registrations er
                where er.event_id = v_reg.event_id and er.status = 'REGISTERED'
             ),
             'avatars', coalesce((
               select jsonb_agg(jsonb_build_object('alias', x.alias, 'avatarColor', x.avatar_color))
                 from (
                   select er.alias, p.avatar_color
                     from public.event_registrations er
                     join public.players p on p.id = er.player_id
                    where er.event_id = v_reg.event_id and er.status = 'REGISTERED'
                    order by er.player_number asc
                    limit 6
                 ) x
             ), '[]'::jsonb),
             'previewAliases', coalesce((
               select jsonb_agg(x.alias)
                 from (
                   select er.alias
                     from public.event_registrations er
                    where er.event_id = v_reg.event_id and er.status = 'REGISTERED'
                    order by er.player_number asc
                    limit 3
                 ) x
             ), '[]'::jsonb)
           )
      into v_social;

    v_payload := v_payload || jsonb_build_object('socialProof', v_social);
  end if;

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

-- ============================================================ 2. coordinator_room_state

-- Everything the Coordinator Home screen needs in one round trip. Reads
-- only — never mutates. Enforces is_authorized_for_room() itself; a route
-- guard is a UX courtesy, this check is the actual authority.
--
-- "Current game" is the lowest-position configured event_game that this
-- room has not yet completed — whether that game is currently LIVE for
-- this room (a coordinator mid-game) or still PENDING (a coordinator who
-- hasn't started it yet, needing the "GET READY / START X" prompt). Once
-- every configured game is COMPLETE for this room, currentGame is null —
-- there is nothing left to start.
create or replace function public.coordinator_room_state(p_room_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
declare
  v_event_id uuid;
  v_current_event_game record;
  v_reg record;
  v_live_round record;
  v_last_round record;
  v_completed_rounds integer;
  v_result jsonb;
begin
  select event_id into v_event_id from rooms where id = p_room_id;
  if v_event_id is null then
    raise exception 'room_not_found: no such room' using errcode = 'no_data_found';
  end if;

  if not public.is_authorized_for_room(p_room_id) then
    raise exception 'not_authorized: not this room''s coordinator or an event admin' using errcode = '42501';
  end if;

  select eg.*, reg.id as room_event_game_id, reg.status as room_status,
         reg.started_at as room_started_at, reg.ended_at as room_ended_at
    into v_current_event_game
    from event_games eg
    left join room_event_games reg on reg.room_id = p_room_id and reg.event_game_id = eg.id
   where eg.event_id = v_event_id
     and (reg.id is null or reg.status <> 'COMPLETE')
   order by eg.position
   limit 1;

  if v_current_event_game.id is not null then
    v_completed_rounds := (
      select count(*) from rounds
       where room_id = p_room_id and event_game_id = v_current_event_game.id and status = 'COMPLETE'
    );

    select id, round_index, started_at into v_live_round
      from rounds
     where room_id = p_room_id and event_game_id = v_current_event_game.id and status = 'LIVE';

    select id, round_index, ended_at into v_last_round
      from rounds
     where room_id = p_room_id and event_game_id = v_current_event_game.id and status = 'COMPLETE'
     order by round_index desc limit 1;
  end if;

  select jsonb_build_object(
    'room', jsonb_build_object(
      'id', ro.id, 'label', ro.label, 'capacity', ro.capacity,
      'occupancy', (select count(*) from room_memberships where room_id = ro.id and left_at is null),
      'roster', (
        select coalesce(jsonb_agg(jsonb_build_object('registrationId', er.id, 'alias', er.alias) order by rm.assigned_at), '[]'::jsonb)
          from room_memberships rm
          join event_registrations er on er.id = rm.registration_id
         where rm.room_id = ro.id and rm.left_at is null
      )
    ),
    'event', jsonb_build_object('slug', e.slug, 'name', e.name),
    'currentGame', case when v_current_event_game.id is null then null else jsonb_build_object(
      'eventGameId', v_current_event_game.id,
      'gameSlug', (select slug from games where id = v_current_event_game.game_id),
      'gameName', (select name from games where id = v_current_event_game.game_id),
      'scoringTemplate', v_current_event_game.scoring_template,
      'scoringConfig', v_current_event_game.scoring_config,
      'plannedRounds', v_current_event_game.planned_rounds,
      'durationMinutes', v_current_event_game.duration_minutes,
      'roomGameStatus', coalesce(v_current_event_game.room_status, 'PENDING'),
      'startedAt', v_current_event_game.room_started_at,
      'endedAt', v_current_event_game.room_ended_at,
      'completedRounds', coalesce(v_completed_rounds, 0),
      'liveRound', case when v_live_round.id is null then null else jsonb_build_object(
        'roundId', v_live_round.id, 'roundIndex', v_live_round.round_index, 'startedAt', v_live_round.started_at
      ) end,
      'lastCompletedRound', case when v_last_round.id is null then null else jsonb_build_object(
        'roundId', v_last_round.id, 'roundIndex', v_last_round.round_index, 'endedAt', v_last_round.ended_at
      ) end
    ) end
  ) into v_result
  from rooms ro join events e on e.id = ro.event_id
  where ro.id = p_room_id;

  return v_result;
end;
$$;

revoke all on function public.coordinator_room_state(uuid) from public;
grant execute on function public.coordinator_room_state(uuid) to authenticated;
