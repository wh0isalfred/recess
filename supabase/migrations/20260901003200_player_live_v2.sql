-- 0032 — Phase 8.3 Gate B: Player Live V2 (room stage).
--
-- Extends get_player_state() to actually understand room_event_games,
-- rounds, round_participants, results, correction_requests, and settled
-- point_transactions — the gap the approved Gate A spec identified: this
-- function previously never read any of that, so LIVE_ROUND/BETWEEN_
-- GAMES/BETWEEN_ROUNDS were tagged in the TypeScript union but never
-- actually produced.
--
-- Also fixes a real drift risk found while building this: complete_room_
-- game()'s own "is this room-game eligible to complete" logic is now
-- extracted into room_game_ready_to_settle(), called by BOTH complete_
-- room_game() and get_player_state() — so activeGame.awaitingGameSettlement
-- can never silently disagree with what complete_room_game() would
-- actually allow.

-- ============================================================ 1. shared eligibility helper

-- Exactly complete_room_game()'s own gate, extracted so it exists in one
-- place. True iff: a room_event_games row exists for this room+game,
-- status is LIVE, no round is LIVE, and EITHER the planned round count
-- is reached OR the configured duration window has expired. VOID rounds
-- never count toward "planned round count reached" — they're simply not
-- status='COMPLETE'.
create or replace function public.room_game_ready_to_settle(p_room_id uuid, p_event_game_id uuid)
returns boolean
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
declare
  v_row record;
  v_event_game record;
  v_completed_count integer;
  v_window_expired boolean;
begin
  select * into v_row from room_event_games
   where room_id = p_room_id and event_game_id = p_event_game_id;
  if not found or v_row.status <> 'LIVE' then
    return false;
  end if;

  if exists (
    select 1 from rounds
     where room_id = p_room_id and event_game_id = p_event_game_id and status = 'LIVE'
  ) then
    return false;
  end if;

  select * into v_event_game from event_games where id = p_event_game_id;

  select count(*) into v_completed_count from rounds
   where room_id = p_room_id and event_game_id = p_event_game_id and status = 'COMPLETE';

  v_window_expired := v_event_game.duration_minutes is not null
    and v_row.started_at is not null
    and now() > v_row.started_at + (v_event_game.duration_minutes || ' minutes')::interval;

  return v_completed_count >= v_event_game.planned_rounds or v_window_expired;
end;
$$;

revoke all on function public.room_game_ready_to_settle(uuid, uuid) from public;

-- ============================================================ 2. complete_room_game() — same contract, now calls the shared helper

-- Identical signature, authorization, and observable behavior to the
-- version this supersedes (diffed to confirm) — the only change is that
-- its own eligibility check now delegates to room_game_ready_to_settle()
-- instead of repeating the same three conditions inline, so this
-- function and get_player_state() can never quietly drift apart on what
-- "ready to complete" means.
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

  if not public.room_game_ready_to_settle(p_room_id, p_event_game_id) then
    select * into v_event_game from event_games where id = p_event_game_id;
    select count(*) into v_completed_count from rounds
     where room_id = p_room_id and event_game_id = p_event_game_id and status = 'COMPLETE';
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

-- ============================================================ 3. get_player_state() V2

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

  -- room-stage additions
  v_coordinator_alias text;
  v_current_eg   record;
  v_has_started_any_game boolean;
  v_completed_rounds integer;
  v_live_round   record;
  v_last_round   record;
  v_last_result_submitted_at timestamptz;
  v_last_result_participation public.participation_state;
  v_last_result_role_key text;
  v_last_result_raw_score numeric;
  v_pending      boolean;
  v_ready_to_settle boolean;
  v_active_game  jsonb;
  v_last_completed_game jsonb;
  v_next_game    jsonb;
  v_championship jsonb;
  v_visibility   public.leaderboard_visibility;
  v_show_placement boolean;
  v_room_stage_exhausted boolean := false;
begin
  v_uid := auth.uid();
  if v_uid is null then
    return null;
  end if;

  select r.id, r.alias, r.player_number, r.status, r.checked_in_at, r.event_id,
         e.slug as event_slug, e.name as event_name, e.status as event_status,
         e.starts_at, e.timezone, e.timezone_label, e.whatsapp_group_url,
         e.checkin_opens_at, e.checkin_closes_at, e.leaderboard_visibility,
         p.avatar_color
    into v_reg
    from public.event_registrations r
    join public.events e on e.id = r.event_id
    join public.players p on p.id = r.player_id
   where r.player_id = public.current_player_id()
   order by r.created_at desc
   limit 1;

  if not found then
    return null;
  end if;

  v_avatar_color := v_reg.avatar_color;
  v_visibility := v_reg.leaderboard_visibility;

  select rm.id, rm.room_id, rm2.label as room_label, rm2.capacity as room_capacity,
         rm2.whatsapp_group_url as room_whatsapp_url
    into v_membership
    from public.room_memberships rm
    join public.rooms rm2 on rm2.id = rm.room_id
   where rm.registration_id = v_reg.id and rm.left_at is null;

  v_checkin_available :=
    (v_reg.checkin_opens_at is null or now() >= v_reg.checkin_opens_at)
    and (v_reg.checkin_closes_at is null or now() < v_reg.checkin_closes_at);

  -- ---------------------------------------------------------- view precedence

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
    elsif v_reg.event_status = 'PAUSED' then
      v_view := 'PAUSED';
    elsif v_membership.id is null then
      v_view := 'CHECKED_IN_WAITING';
    else
      -- Checked in, has a room, event genuinely LIVE — derive room
      -- progression. Same "lowest-position not-yet-complete-for-this-
      -- room" query coordinator_room_state() already uses, reused here
      -- rather than reinvented.
      select eg.*, reg.status as room_status, reg.started_at as room_started_at, reg.ended_at as room_ended_at
        into v_current_eg
        from event_games eg
        left join room_event_games reg on reg.room_id = v_membership.room_id and reg.event_game_id = eg.id
       where eg.event_id = v_reg.event_id
         and (reg.id is null or reg.status <> 'COMPLETE')
       order by eg.position
       limit 1;

      select exists (
        select 1 from room_event_games where room_id = v_membership.room_id
      ) into v_has_started_any_game;

      if v_current_eg.id is null then
        -- Every configured game is COMPLETE for this room (or none were
        -- ever configured) — the room stage is over. Real qualification
        -- decided below, once championship is computed.
        v_room_stage_exhausted := true;
      elsif v_current_eg.room_status is null or v_current_eg.room_status = 'PENDING' then
        v_view := case when v_has_started_any_game then 'BETWEEN_GAMES' else 'ROOM_ASSIGNED' end;
      else
        -- room_status = 'LIVE' (can't be COMPLETE — excluded by the query above)
        select id, round_index, started_at into v_live_round
          from rounds
         where room_id = v_membership.room_id and event_game_id = v_current_eg.id and status = 'LIVE';
        v_view := case when v_live_round.id is not null then 'LIVE_ROUND' else 'BETWEEN_ROUNDS' end;
      end if;
    end if;
  else
    -- events.status = 'COMPLETE' is the only remaining value reachable here.
    v_view := 'RESULTS';
  end if;

  -- ---------------------------------------------------------- coordinator (unconditional)

  select jsonb_build_object('roomId', rc.room_id, 'roomLabel', ro.label)
    into v_coordinating
    from public.room_coordinators rc
    join public.rooms ro on ro.id = rc.room_id
   where rc.registration_id = v_reg.id and rc.replaced_at is null;

  -- ---------------------------------------------------------- room-stage data

  if v_membership.id is not null then
    select er.alias into v_coordinator_alias
      from room_coordinators rc
      join event_registrations er on er.id = rc.registration_id
     where rc.room_id = v_membership.room_id and rc.replaced_at is null;
  end if;

  if v_view in ('LIVE_ROUND', 'BETWEEN_ROUNDS') then
    v_completed_rounds := (
      select count(*) from rounds
       where room_id = v_membership.room_id and event_game_id = v_current_eg.id and status = 'COMPLETE'
    );

    select id, round_index into v_last_round
      from rounds
     where room_id = v_membership.room_id and event_game_id = v_current_eg.id and status = 'COMPLETE'
     order by round_index desc limit 1;

    v_last_result_submitted_at := null;
    v_last_result_participation := null;
    v_last_result_role_key := null;
    v_last_result_raw_score := null;
    v_pending := false;
    if v_last_round.id is not null then
      select res.submitted_at, rp.participation, rp.role_key, rp.raw_score
        into v_last_result_submitted_at, v_last_result_participation, v_last_result_role_key, v_last_result_raw_score
        from results res
        join round_participants rp on rp.round_id = res.round_id and rp.registration_id = v_reg.id
       where res.round_id = v_last_round.id and res.superseded_at is null;

      select exists (
        select 1 from correction_requests
         where round_id = v_last_round.id and status = 'PENDING'
      ) into v_pending;
    end if;

    v_ready_to_settle := public.room_game_ready_to_settle(v_membership.room_id, v_current_eg.id);

    v_active_game := jsonb_build_object(
      'gameSlug', (select slug from games where id = v_current_eg.game_id),
      'gameName', coalesce(v_current_eg.display_name, (select name from games where id = v_current_eg.game_id)),
      'platform', (select platform from games where id = v_current_eg.game_id),
      'platformUrl', (select platform_url from games where id = v_current_eg.game_id),
      'artworkUrl', (select artwork_url from games where id = v_current_eg.game_id),
      'scoringTemplate', v_current_eg.scoring_template,
      'plannedRounds', v_current_eg.planned_rounds,
      'completedRounds', coalesce(v_completed_rounds, 0),
      'durationMinutes', v_current_eg.duration_minutes,
      'startedAt', v_current_eg.room_started_at,
      'liveRound', case when v_live_round.id is not null then jsonb_build_object('roundIndex', v_live_round.round_index) else null end,
      'lastRoundResult', case when v_last_result_participation is null then null else jsonb_build_object(
        'roundIndex', v_last_round.round_index,
        'confirmedAt', v_last_result_submitted_at,
        'yourFact', case
          when v_last_result_participation = 'DNP' then jsonb_build_object('participation', 'DNP')
          when v_current_eg.scoring_template = 'PLACEMENT' then
            jsonb_build_object('participation', v_last_result_participation, 'rawScore', v_last_result_raw_score)
          else
            jsonb_build_object('participation', v_last_result_participation, 'role', v_last_result_role_key)
        end,
        'pending', v_pending
      ) end,
      'awaitingGameSettlement', v_ready_to_settle
    );
  end if;

  if v_view in ('BETWEEN_GAMES', 'QUALIFIED', 'NOT_QUALIFIED') then
    -- The most recently COMPLETE room_event_game for this room (by
    -- ended_at) is "the last completed game" — for BETWEEN_GAMES this is
    -- necessarily the game just finished; for QUALIFIED/NOT_QUALIFIED
    -- it's the room's actual last configured game.
    declare
      v_lcg record;
      v_game_points numeric;
    begin
      select reg.event_game_id, reg.ended_at, eg.display_name, eg.planned_rounds
        into v_lcg
        from room_event_games reg
        join event_games eg on eg.id = reg.event_game_id
       where reg.room_id = v_membership.room_id and reg.status = 'COMPLETE'
       order by reg.ended_at desc
       limit 1;

      if v_lcg.event_game_id is not null then
        select coalesce(sum(points), 0) into v_game_points
          from point_transactions
         where room_event_game_id = (
                 select id from room_event_games
                  where room_id = v_membership.room_id and event_game_id = v_lcg.event_game_id
               )
           and registration_id = v_reg.id
           and voided_at is null;

        v_show_placement := v_visibility <> 'HIDDEN_UNTIL_FINALE';

        v_last_completed_game := jsonb_build_object(
          'gameSlug', (select slug from games g join event_games eg2 on eg2.game_id = g.id where eg2.id = v_lcg.event_game_id),
          'gameName', coalesce(v_lcg.display_name, (select name from games g join event_games eg2 on eg2.game_id = g.id where eg2.id = v_lcg.event_game_id)),
          'yourGamePoints', v_game_points,
          'roomPlacementThisGame', case when not v_show_placement then null else (
            select placement from (
              select registration_id,
                     rank() over (order by total desc) as placement
                from (
                  select rm.registration_id, coalesce(sum(pt.points), 0) as total
                    from room_memberships rm
                    left join point_transactions pt
                      on pt.registration_id = rm.registration_id and pt.voided_at is null
                     and pt.room_event_game_id = (
                           select id from room_event_games
                            where room_id = v_membership.room_id and event_game_id = v_lcg.event_game_id
                         )
                   where rm.room_id = v_membership.room_id and rm.left_at is null
                   group by rm.registration_id
                ) totals
            ) ranked
            where ranked.registration_id = v_reg.id
          ) end
        );
      end if;
    end;
  end if;

  -- ---------------------------------------------------------- next game

  if v_view = 'ROOM_ASSIGNED' then
    select jsonb_build_object(
             'slug', g.slug, 'name', coalesce(eg.display_name, g.name), 'platform', g.platform,
             'artworkUrl', g.artwork_url, 'iconUrl', g.icon_url
           )
      into v_next_game
      from public.event_games eg
      join public.games g on g.id = eg.game_id
     where eg.event_id = v_reg.event_id and g.status = 'ACTIVE'
     order by eg.position
     limit 1;
  elsif v_view = 'BETWEEN_GAMES' then
    select jsonb_build_object(
             'slug', g.slug, 'name', coalesce(eg.display_name, g.name), 'platform', g.platform,
             'artworkUrl', g.artwork_url, 'iconUrl', g.icon_url
           )
      into v_next_game
      from event_games eg
      join games g on g.id = eg.game_id
      left join room_event_games reg on reg.room_id = v_membership.room_id and reg.event_game_id = eg.id
     where eg.event_id = v_reg.event_id
       and (reg.id is null or reg.status <> 'COMPLETE')
     order by eg.position
     limit 1;
  end if;

  -- ---------------------------------------------------------- championship / qualification

  if v_room_stage_exhausted then
    -- room-stage complete for this room: resolve QUALIFIED/NOT_QUALIFIED now.
    declare
      v_total numeric;
      v_placement integer;
    begin
      select total, placement into v_total, v_placement
        from (
          select rm.registration_id,
                 coalesce(sum(pt.points), 0) as total,
                 rank() over (order by coalesce(sum(pt.points), 0) desc) as placement
            from room_memberships rm
            left join point_transactions pt
              on pt.registration_id = rm.registration_id and pt.voided_at is null and pt.event_id = v_reg.event_id
           where rm.room_id = v_membership.room_id and rm.left_at is null
           group by rm.registration_id
        ) ranked
       where ranked.registration_id = v_reg.id;

      v_view := case when v_placement <= 2 then 'QUALIFIED' else 'NOT_QUALIFIED' end;

      v_show_placement := v_visibility <> 'HIDDEN_UNTIL_FINALE';
      v_championship := jsonb_build_object(
        'yourTotalPoints', coalesce(v_total, 0),
        'qualifies', v_placement <= 2,
        'roomPlacement', case when v_show_placement then v_placement else null end,
        'finaleInProgress', false,
        'finalResults', null
      );
    end;

    -- Recompute lastCompletedGame now that v_view is resolved (the block
    -- above ran before v_view was known to be QUALIFIED/NOT_QUALIFIED).
    declare
      v_lcg2 record;
      v_game_points2 numeric;
    begin
      select reg.event_game_id, reg.ended_at, eg.display_name
        into v_lcg2
        from room_event_games reg
        join event_games eg on eg.id = reg.event_game_id
       where reg.room_id = v_membership.room_id and reg.status = 'COMPLETE'
       order by reg.ended_at desc
       limit 1;

      if v_lcg2.event_game_id is not null then
        select coalesce(sum(points), 0) into v_game_points2
          from point_transactions
         where room_event_game_id = (
                 select id from room_event_games
                  where room_id = v_membership.room_id and event_game_id = v_lcg2.event_game_id
               )
           and registration_id = v_reg.id
           and voided_at is null;

        v_last_completed_game := jsonb_build_object(
          'gameSlug', (select slug from games g join event_games eg2 on eg2.game_id = g.id where eg2.id = v_lcg2.event_game_id),
          'gameName', coalesce(v_lcg2.display_name, (select name from games g join event_games eg2 on eg2.game_id = g.id where eg2.id = v_lcg2.event_game_id)),
          'yourGamePoints', v_game_points2,
          'roomPlacementThisGame', null
        );
      end if;
    end;
  end if;

  -- ---------------------------------------------------------- assemble payload

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

  if v_membership.id is not null then
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
        ),
        'coordinatorAlias', v_coordinator_alias
      )
    );
  end if;

  if v_active_game is not null then
    v_payload := v_payload || jsonb_build_object('activeGame', v_active_game);
  end if;
  if v_last_completed_game is not null then
    v_payload := v_payload || jsonb_build_object('lastCompletedGame', v_last_completed_game);
  end if;
  if v_next_game is not null then
    v_payload := v_payload || jsonb_build_object('nextGame', v_next_game);
    -- Deprecated compatibility field — see migration comment. Remove once
    -- the frontend that reads upFirstGame is confirmed retired.
    if v_view = 'ROOM_ASSIGNED' then
      v_payload := v_payload || jsonb_build_object('upFirstGame', v_next_game);
    end if;
  elsif v_view = 'ROOM_ASSIGNED' then
    v_payload := v_payload || jsonb_build_object('upFirstGame', null);
  end if;
  if v_championship is not null then
    v_payload := v_payload || jsonb_build_object('championship', v_championship);
  end if;

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

  return v_payload;
end;
$$;

-- ============================================================ 4. get_my_game_progress()

-- /games — the map of the night. No arguments: entirely derived from
-- auth.uid() -> current_player_id() -> the caller's own registration and
-- room. Shows the event's configured games in position order, each
-- marked from the caller's own room's progression — never another
-- room's. Before room assignment, still returns the sequence (with every
-- item PENDING) rather than pretending the player has room-specific
-- progress they don't have yet.
create or replace function public.get_my_game_progress()
returns jsonb
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
declare
  v_player_id uuid;
  v_reg record;
  v_room_id uuid;
  v_visibility public.leaderboard_visibility;
begin
  v_player_id := public.current_player_id();
  if v_player_id is null then
    raise exception 'not_registered: no registration found for this session' using errcode = 'no_data_found';
  end if;

  select er.event_id, e.leaderboard_visibility into v_reg
    from event_registrations er join events e on e.id = er.event_id
   where er.player_id = v_player_id
   order by er.created_at desc limit 1;
  v_visibility := v_reg.leaderboard_visibility;

  select room_id into v_room_id from room_memberships
   where registration_id in (select id from event_registrations where player_id = v_player_id)
     and left_at is null
   limit 1;

  return coalesce((
    select jsonb_agg(jsonb_build_object(
             'slug', g.slug,
             'name', coalesce(eg.display_name, g.name),
             'platform', g.platform,
             'artworkUrl', g.artwork_url,
             'plannedRounds', eg.planned_rounds,
             'status', case
               when v_room_id is null then 'PENDING'
               else coalesce((
                 select reg.status::text from room_event_games reg
                  where reg.room_id = v_room_id and reg.event_game_id = eg.id
               ), 'PENDING')
             end,
             'completedRounds', case
               when v_room_id is null then 0
               else (
                 select count(*) from rounds
                  where room_id = v_room_id and event_game_id = eg.id and status = 'COMPLETE'
               )
             end,
             -- Own settled points, only once this specific room-game is
             -- COMPLETE — same rule get_player_state() uses, never a
             -- guess at an in-progress total.
             'yourGamePoints', case
               when v_room_id is null then null
               when (select reg.status from room_event_games reg
                      where reg.room_id = v_room_id and reg.event_game_id = eg.id) = 'COMPLETE'
               then (
                 select coalesce(sum(pt.points), 0) from point_transactions pt
                  where pt.room_event_game_id = (
                          select reg.id from room_event_games reg
                           where reg.room_id = v_room_id and reg.event_game_id = eg.id
                        )
                    and pt.registration_id in (select id from event_registrations where player_id = v_player_id and event_id = v_reg.event_id)
                    and pt.voided_at is null
               )
               else null
             end
           ) order by eg.position)
      from event_games eg
      join games g on g.id = eg.game_id
     where eg.event_id = v_reg.event_id and g.status = 'ACTIVE'
  ), '[]'::jsonb);
end;
$$;

revoke all on function public.get_my_game_progress() from public;
grant execute on function public.get_my_game_progress() to authenticated;

-- ============================================================ 5. get_my_room_standings()

-- /players — the caller's own room, roster, and standings when
-- leaderboard_visibility permits. Zero arguments, same derivation chain.
-- Never returns registrationId to an ordinary player — alias, points,
-- placement only. Reuses room_standings_compute() internally (the same
-- helper the coordinator standings hotfix introduced) and strips the
-- registrationId field before returning, rather than a third independent
-- computation of the same numbers.
create or replace function public.get_my_room_standings()
returns jsonb
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
declare
  v_player_id uuid;
  v_room_id uuid;
  v_event_id uuid;
  v_visibility public.leaderboard_visibility;
  v_raw jsonb;
begin
  v_player_id := public.current_player_id();
  if v_player_id is null then
    raise exception 'not_registered: no registration found for this session' using errcode = 'no_data_found';
  end if;

  select rm.room_id, er.event_id into v_room_id, v_event_id
    from event_registrations er
    join room_memberships rm on rm.registration_id = er.id and rm.left_at is null
   where er.player_id = v_player_id
   order by er.created_at desc limit 1;

  if v_room_id is null then
    return jsonb_build_object('room', null, 'standings', null);
  end if;

  select e.leaderboard_visibility into v_visibility from events e where e.id = v_event_id;

  if v_visibility = 'HIDDEN_UNTIL_FINALE' then
    return jsonb_build_object(
      'room', (select label from rooms where id = v_room_id),
      'standings', null
    );
  end if;

  v_raw := public.room_standings_compute(v_room_id, v_event_id);

  return jsonb_build_object(
    'room', (select label from rooms where id = v_room_id),
    'standings', (
      select coalesce(jsonb_agg(jsonb_build_object(
               'alias', elem->>'alias',
               'totalPoints', (elem->>'totalPoints')::numeric,
               'placement', (elem->>'placement')::int
             ) order by (elem->>'placement')::int, elem->>'alias'), '[]'::jsonb)
        from jsonb_array_elements(v_raw) elem
    )
  );
end;
$$;

revoke all on function public.get_my_room_standings() from public;
grant execute on function public.get_my_room_standings() to authenticated;
