-- Test 49 — Phase 7.1: Scoring Engine hardening (migration 0027).
begin;
select plan(14);

create or replace function pg_temp.as_staff(p_uid uuid, p_role public.staff_role) returns void
language sql as $$
  insert into auth.users (id) values (p_uid);
  insert into public.staff_profiles (user_id, name, role) values (p_uid, 'Test Staff', p_role);
  select set_config('request.jwt.claim.sub', p_uid::text, true);
$$;

create or replace function pg_temp.as_player_session(p_registration_id uuid) returns void
language plpgsql as $$
declare v_uid uuid := gen_random_uuid();
begin
  insert into auth.users (id) values (v_uid);
  update event_registrations set auth_user_id = v_uid where id = p_registration_id;
  perform set_config('request.jwt.claim.sub', v_uid::text, true);
end $$;

create or replace function pg_temp.register(p_event_id uuid, p_alias text, p_phone text) returns uuid
language plpgsql as $$
declare v_player_id uuid; v_reg_id uuid; v_no int;
begin
  insert into public.players (phone_e164, real_name, canonical_alias) values (p_phone, p_alias, p_alias) returning id into v_player_id;
  update public.event_counters set next_player_no = next_player_no + 1
   where event_id = p_event_id returning next_player_no - 1 into v_no;
  insert into public.event_registrations (event_id, player_id, alias, player_number, status, auth_user_id)
  values (p_event_id, v_player_id, p_alias, v_no, 'REGISTERED', gen_random_uuid()) returning id into v_reg_id;
  return v_reg_id;
end $$;

-- ---------------------------------------------------------------------- fixture

select pg_temp.as_staff(gen_random_uuid(), 'SUPER_ADMIN');

insert into public.events (slug, name, status, starts_at, timezone, timezone_label, capacity)
values ('test-hard27', 'Hardening Event', 'LIVE', now() - interval '1 hour', 'Africa/Lagos', 'WAT', 30);
create temporary table ev27 as select id from public.events where slug = 'test-hard27';

insert into public.games (slug, name, platform, scoring_template, status, artwork_url, default_round_count)
values ('test-au27', 'Test Among Us 27', 'INSTALL', 'ROLE_OUTCOME', 'ACTIVE', '/games/test-au27.webp', 2);

-- A 2-round-max game, so the ceiling is reachable quickly.
insert into event_games (event_id, game_id, position, scoring_template, planned_rounds, scoring_config)
select (select id from ev27), id, 1, 'ROLE_OUTCOME', 2,
       jsonb_build_object('awards', jsonb_build_object(
         'crewmate', jsonb_build_object('win', 1, 'loss', 0),
         'impostor', jsonb_build_object('win', 2, 'loss', 0)
       ))
  from games where slug = 'test-au27';
create temporary table auGame27 as select id from event_games where event_id = (select id from ev27) and position = 1;

select pg_temp.register((select id from ev27), 'hcoord', '+2348080000001');
select public.admin_create_room('test-hard27', 'HARD ROOM 01', 8,
  (select id from public.event_registrations where alias = 'hcoord'));
create temporary table hroom as select id from rooms where event_id = (select id from ev27) and label = 'HARD ROOM 01';

select pg_temp.register((select id from ev27), 'h1', '+2348080000011');
select pg_temp.register((select id from ev27), 'h2', '+2348080000012');
insert into room_memberships (event_id, room_id, registration_id)
select (select id from ev27), (select id from hroom), id from event_registrations where alias in ('h1','h2');

select public.start_room_game((select id from hroom), (select id from auGame27));

-- ==================================================================== 1. MAX ROUNDS

select lives_ok(
  $$ select public.start_round((select id from hroom), (select id from auGame27)) $$,
  'test 49: round 1 of a 2-max game starts fine');
create temporary table hround1 as select id from rounds where room_id=(select id from hroom) and event_game_id=(select id from auGame27) and round_index=1;
select public.submit_round_result(
  (select id from hround1),
  jsonb_build_object('winningRole','crewmate','participants', jsonb_build_array(
    jsonb_build_object('registrationId',(select id from event_registrations where alias='h1'),'participation','PARTICIPATING','role','crewmate'),
    jsonb_build_object('registrationId',(select id from event_registrations where alias='h2'),'participation','PARTICIPATING','role','crewmate')
  )), 'idem-hround1-0001'
);

select lives_ok(
  $$ select public.start_round((select id from hroom), (select id from auGame27)) $$,
  'test 49: round 2 of a 2-max game starts fine (at, not yet over, the ceiling)');
create temporary table hround2 as select id from rounds where room_id=(select id from hroom) and event_game_id=(select id from auGame27) and round_index=2;
select public.submit_round_result(
  (select id from hround2),
  jsonb_build_object('winningRole','crewmate','participants', jsonb_build_array(
    jsonb_build_object('registrationId',(select id from event_registrations where alias='h1'),'participation','PARTICIPATING','role','crewmate'),
    jsonb_build_object('registrationId',(select id from event_registrations where alias='h2'),'participation','PARTICIPATING','role','crewmate')
  )), 'idem-hround2-0001'
);

select throws_like(
  $$ select public.start_round((select id from hroom), (select id from auGame27)) $$,
  'rounds_exhausted%',
  'test 49: a third round is refused once 2 of 2 planned rounds are already complete');

-- Void-then-replay does not burn a round slot (SCORING.md §9): void round 2,
-- start a genuine replacement, and confirm the ceiling still only counts
-- COMPLETE rounds (2 completed total: original round 1 + the replacement),
-- not the highest round_index reached (which is now 3).
update rounds set status = 'LIVE' where id = (select id from hround2);
select public.void_round((select id from hround2), 'test fixture: simulate a crash to replay');
select lives_ok(
  $$ select public.start_round((select id from hroom), (select id from auGame27)) $$,
  'test 49: replaying a voided round is allowed — voiding does not burn a completed-round slot');
create temporary table hround3 as select id from rounds where room_id=(select id from hroom) and event_game_id=(select id from auGame27) and round_index=3;
select public.submit_round_result(
  (select id from hround3),
  jsonb_build_object('winningRole','crewmate','participants', jsonb_build_array(
    jsonb_build_object('registrationId',(select id from event_registrations where alias='h1'),'participation','PARTICIPATING','role','crewmate'),
    jsonb_build_object('registrationId',(select id from event_registrations where alias='h2'),'participation','PARTICIPATING','role','crewmate')
  )), 'idem-hround3-0001'
);
select throws_like(
  $$ select public.start_round((select id from hroom), (select id from auGame27)) $$,
  'rounds_exhausted%',
  'test 49: after the replay, the ceiling is enforced again — 2 real completed rounds, no more');

-- Room can only have one game LIVE at a time (Phase 6.5) — complete
-- auGame27 here before skGame27 can start in the same room.
select public.complete_room_game((select id from hroom), (select id from auGame27));

-- ==================================================================== 2. GAME WINDOW

insert into public.games (slug, name, platform, scoring_template, status, artwork_url, default_round_count)
values ('test-sk27', 'Test Skribbl 27', 'BROWSER', 'PLACEMENT', 'ACTIVE', '/games/test-sk27.webp', 5);
insert into event_games (event_id, game_id, position, scoring_template, planned_rounds, duration_minutes, scoring_config)
select (select id from ev27), id, 2, 'PLACEMENT', 5, 30, jsonb_build_object('type','placement')
  from games where slug = 'test-sk27';
create temporary table skGame27 as select id from event_games where event_id=(select id from ev27) and position=2;

select public.start_room_game((select id from hroom), (select id from skGame27));
-- Backdate the room-game's own start far enough that its 30-minute window
-- has already elapsed — this is the room's real, existing started_at
-- column (Phase 6.5), not a new field.
update room_event_games set started_at = now() - interval '45 minutes'
 where room_id = (select id from hroom) and event_game_id = (select id from skGame27);

select throws_like(
  $$ select public.start_round((select id from hroom), (select id from skGame27)) $$,
  'game_window_expired%',
  'test 49: a round cannot start once the configured game window has elapsed');

-- Admin intervention: extending duration_minutes (the existing config
-- model) re-opens the window on the very next call — no bypass invented.
select public.admin_update_event_game('test-hard27', (select id from skGame27), 120, null);
select lives_ok(
  $$ select public.start_round((select id from hroom), (select id from skGame27)) $$,
  'test 49: an Admin extending duration_minutes re-opens the window immediately');
create temporary table skround1 as select id from rounds where room_id=(select id from hroom) and event_game_id=(select id from skGame27) and round_index=1;
select public.void_round((select id from skround1), 'test fixture cleanup');

-- No configured duration at all -> no enforceable window, not a block.
-- A genuinely separate room, since skGame27 needs to stay LIVE in hroom for
-- the cross-round idempotency test later — completing it here would block
-- that (one live game per room, Phase 6.5).
select pg_temp.register((select id from ev27), 'hcoord2', '+2348080000002');
select public.admin_create_room('test-hard27', 'HARD ROOM 02', 8,
  (select id from public.event_registrations where alias = 'hcoord2'));
create temporary table hroom2 as select id from rooms where event_id = (select id from ev27) and label = 'HARD ROOM 02';
select pg_temp.register((select id from ev27), 'h3', '+2348080000013');
select pg_temp.register((select id from ev27), 'h4', '+2348080000014');
insert into room_memberships (event_id, room_id, registration_id)
select (select id from ev27), (select id from hroom2), id from event_registrations where alias in ('h3','h4');

insert into public.games (slug, name, platform, scoring_template, status, artwork_url, default_round_count)
values ('test-tv27', 'Test Trivia 27', 'BROWSER', 'PLACEMENT', 'ACTIVE', '/games/test-tv27.webp', 5);
insert into event_games (event_id, game_id, position, scoring_template, planned_rounds, duration_minutes, scoring_config)
select (select id from ev27), id, 3, 'PLACEMENT', 5, null, jsonb_build_object('type','placement')
  from games where slug = 'test-tv27';
create temporary table tvGame27 as select id from event_games where event_id=(select id from ev27) and position=3;

-- Phase 6.5's game order is enforced per-room: hroom2 must complete
-- positions 1 and 2 for itself (never having played either) before
-- starting position 3 — no rounds are needed to satisfy this, just the
-- room-game lifecycle itself.
select public.start_room_game((select id from hroom2), (select id from auGame27));
select public.complete_room_game((select id from hroom2), (select id from auGame27));
select public.start_room_game((select id from hroom2), (select id from skGame27));
select public.complete_room_game((select id from hroom2), (select id from skGame27));

select public.start_room_game((select id from hroom2), (select id from tvGame27));
update room_event_games set started_at = now() - interval '999 hours'
 where room_id = (select id from hroom2) and event_game_id = (select id from tvGame27);
select lives_ok(
  $$ select public.start_round((select id from hroom2), (select id from tvGame27)) $$,
  'test 49: a game with no configured duration has no enforceable window, however long ago it started');

-- ==================================================================== 3. PAYLOAD SET VALIDATION

create temporary table tvround1 as select id from rounds where room_id=(select id from hroom2) and event_game_id=(select id from tvGame27) and round_index=1;

-- Duplicate h3, missing h4 entirely — same array length as the snapshot,
-- wrong set.
select throws_like(
  $$ select public.submit_round_result(
       (select id from tvround1),
       jsonb_build_object('scores', jsonb_build_array(
         jsonb_build_object('registrationId', (select id from event_registrations where alias='h3'), 'participation','PARTICIPATING','rawScore', 100),
         jsonb_build_object('registrationId', (select id from event_registrations where alias='h3'), 'participation','PARTICIPATING','rawScore', 200)
       )),
       'idem-dup-missing-0001'
     ) $$,
  'payload_participant_mismatch%',
  'test 49: a payload with one participant duplicated and another entirely missing is rejected, even at the correct array length');

-- ==================================================================== 4. IDEMPOTENCY AUTHORIZATION

select public.submit_round_result(
  (select id from tvround1),
  jsonb_build_object('scores', jsonb_build_array(
    jsonb_build_object('registrationId', (select id from event_registrations where alias='h3'), 'participation','PARTICIPATING','rawScore', 100),
    jsonb_build_object('registrationId', (select id from event_registrations where alias='h4'), 'participation','PARTICIPATING','rawScore', 200)
  )),
  'idem-tvround1-shared-0001'
);
select is(
  (select public.submit_round_result((select id from tvround1), '{}'::jsonb, 'idem-tvround1-shared-0001')->>'idempotent'),
  'true',
  'test 49: the same key + the same round it actually belongs to remains a safe idempotent retry');
select is(
  (select count(*) from results where round_id = (select id from tvround1)),
  1::bigint,
  'test 49: the idempotent retry created no duplicate result');

select public.start_round((select id from hroom), (select id from skGame27));
create temporary table skround2 as select id from rounds where room_id=(select id from hroom) and event_game_id=(select id from skGame27) and round_index=2;
select throws_like(
  $$ select public.submit_round_result(
       (select id from skround2),
       jsonb_build_object('scores', jsonb_build_array(
         jsonb_build_object('registrationId', (select id from event_registrations where alias='h1'), 'participation','PARTICIPATING','rawScore', 1),
         jsonb_build_object('registrationId', (select id from event_registrations where alias='h2'), 'participation','PARTICIPATING','rawScore', 2)
       )),
       'idem-tvround1-shared-0001'
     ) $$,
  'idempotency_key_reused%',
  'test 49: the same key against a genuinely different round is rejected, not silently resolved against the original round');
select is(
  (select count(*) from results where round_id = (select id from skround2)),
  0::bigint,
  'test 49: the rejected cross-round reuse created no result for the second round at all');

select pg_temp.as_player_session((select id from event_registrations where alias = 'h1'));
select throws_ok(
  $$ select public.submit_round_result(
       (select id from skround2),
       '{}'::jsonb,
       'idem-tvround1-shared-0001'
     ) $$,
  '42501', null,
  'test 49: an unauthorized ordinary player presenting a known/reused key is still refused on authorization first, before any idempotency logic runs');

select * from finish();
rollback;
