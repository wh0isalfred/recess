-- 0023 — pre-Phase-7 alignment: finish event-game configuration.
--
-- Phase 6.5 (0021) gave admin_add_event_game() an optional
-- p_duration_minutes override but left planned_rounds un-overridable at
-- add-time (always copied from the game library's default_round_count) and
-- gave Admin no way to change EITHER value once an event_game row exists —
-- the only two knobs EVENT-OPS.md describes as "Admin-configured" (§5) had
-- no real configuration path for one of them and no edit path for either.
-- This migration closes both gaps:
--
--   1. admin_add_event_game() gains p_planned_rounds, following the exact
--      pattern p_duration_minutes already established: optional, falls
--      back to the library default via coalesce() when omitted, never a
--      hardcoded per-game number.
--   2. admin_update_event_game() — new — lets Admin change either value on
--      an existing event_game row after creation, same authorization and
--      validation as add, audited the same way.
--
-- Neither function builds or implies a running clock — start_room_game()
-- (0021) already anchors a room's actual timer from its own started_at;
-- these values remain configuration read by that mechanism, not the
-- mechanism itself. No Live Control or Coordinator UI is added here.

-- --------------------------------------------------------- admin_add_event_game

-- Same reasoning 0021 already gives for why this is a DROP, not an
-- overloaded CREATE OR REPLACE: Postgres resolves functions by full
-- parameter signature, so leaving the 4-argument version in place
-- alongside a new 5-argument one would not "replace" it — it would be a
-- second, real, dangling overload. 0021 itself (already deployed) is not
-- touched; only the function it defined is dropped and recreated here.
drop function if exists public.admin_add_event_game(text, uuid, integer, integer);

create or replace function public.admin_add_event_game(
  p_event_slug text,
  p_game_id    uuid,
  p_position   integer,
  p_duration_minutes integer default null,
  p_planned_rounds   integer default null
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
  if p_duration_minutes is not null and p_duration_minutes <= 0 then
    raise exception 'invalid_duration: duration must be a positive number of minutes' using errcode = '22023';
  end if;
  if p_planned_rounds is not null and p_planned_rounds <= 0 then
    raise exception 'invalid_rounds: planned rounds must be a positive number' using errcode = '22023';
  end if;

  begin
    insert into event_games (event_id, game_id, position, scoring_template, planned_rounds, duration_minutes)
    values (
      v_event_id, v_game.id, p_position, v_game.scoring_template,
      coalesce(p_planned_rounds, v_game.default_round_count),
      coalesce(p_duration_minutes, v_game.default_duration_minutes)
    )
    returning * into v_event_game;
  exception when unique_violation then
    raise exception 'game_already_added: this game is already in the event' using errcode = '23505';
  end;

  insert into audit_logs (event_id, actor_user_id, action, entity_type, entity_id, after)
  values (v_event_id, v_uid, 'event_game.added', 'event_games', v_event_game.id,
          jsonb_build_object('gameSlug', v_game.slug, 'position', p_position,
                              'durationMinutes', v_event_game.duration_minutes,
                              'plannedRounds', v_event_game.planned_rounds));

  return jsonb_build_object('id', v_event_game.id, 'gameSlug', v_game.slug, 'position', p_position,
                             'durationMinutes', v_event_game.duration_minutes,
                             'plannedRounds', v_event_game.planned_rounds);
end;
$$;

revoke all on function public.admin_add_event_game(text, uuid, integer, integer, integer) from public;
grant execute on function public.admin_add_event_game(text, uuid, integer, integer, integer) to authenticated;

-- ------------------------------------------------------ admin_update_event_game

-- Edits an existing event_game's configuration only — duration_minutes and
-- planned_rounds. Deliberately does not touch position (reordering
-- configured games is a different, riskier operation this migration does
-- not attempt) or scoring_template (Scoring Engine V1's concern, not this
-- alignment pass's). Both parameters are independently optional: pass one,
-- the other, or both — whichever the Admin actually changed.
create or replace function public.admin_update_event_game(
  p_event_slug text,
  p_event_game_id uuid,
  p_duration_minutes integer default null,
  p_planned_rounds   integer default null
) returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_uid uuid := auth.uid();
  v_event_id uuid;
  v_before record;
  v_event_game public.event_games;
begin
  perform public.require_event_admin();

  select id into v_event_id from events where slug = p_event_slug;
  if not found then
    raise exception 'event_not_found: no such event' using errcode = 'no_data_found';
  end if;

  if p_duration_minutes is not null and p_duration_minutes <= 0 then
    raise exception 'invalid_duration: duration must be a positive number of minutes' using errcode = '22023';
  end if;
  if p_planned_rounds is not null and p_planned_rounds <= 0 then
    raise exception 'invalid_rounds: planned rounds must be a positive number' using errcode = '22023';
  end if;

  select * into v_before from event_games where id = p_event_game_id and event_id = v_event_id for update;
  if not found then
    raise exception 'event_game_not_found: this game is not configured for this event' using errcode = 'no_data_found';
  end if;

  update event_games
     set duration_minutes = coalesce(p_duration_minutes, duration_minutes),
         planned_rounds   = coalesce(p_planned_rounds, planned_rounds)
   where id = p_event_game_id
   returning * into v_event_game;

  insert into audit_logs (event_id, actor_user_id, action, entity_type, entity_id, before, after)
  values (v_event_id, v_uid, 'event_game.updated', 'event_games', v_event_game.id,
          jsonb_build_object('durationMinutes', v_before.duration_minutes, 'plannedRounds', v_before.planned_rounds),
          jsonb_build_object('durationMinutes', v_event_game.duration_minutes, 'plannedRounds', v_event_game.planned_rounds));

  return jsonb_build_object('id', v_event_game.id, 'durationMinutes', v_event_game.duration_minutes,
                             'plannedRounds', v_event_game.planned_rounds);
end;
$$;

revoke all on function public.admin_update_event_game(text, uuid, integer, integer) from public;
grant execute on function public.admin_update_event_game(text, uuid, integer, integer) to authenticated;

-- ------------------------------------------------------------- admin_list_games

-- Additive only: defaultDurationMinutes didn't exist when this function was
-- first written (0019) — games.default_duration_minutes was added afterward,
-- in 0021. Without it, the Admin UI has no sensible placeholder to show for
-- a game's duration before an override is typed in.
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
             'scoringTemplate', g.scoring_template, 'defaultRoundCount', g.default_round_count,
             'defaultDurationMinutes', g.default_duration_minutes
           ) order by g.name), '[]'::jsonb)
      from games g where g.status = 'ACTIVE'
  );
end;
$$;
