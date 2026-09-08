-- Test 51 — Phase 8 backend support (migration 0029):
-- get_player_state()'s coordinating field, and coordinator_room_state().
begin;
select plan(12);

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
values ('test-coord29', 'Coordinator Event', 'LIVE', now() - interval '1 hour', 'Africa/Lagos', 'WAT', 30);
create temporary table ev29 as select id from public.events where slug = 'test-coord29';

insert into public.games (slug, name, platform, scoring_template, status, artwork_url, default_round_count)
values ('test-au29', 'Test Among Us 29', 'INSTALL', 'ROLE_OUTCOME', 'ACTIVE', '/games/test-au29.webp', 1);
insert into event_games (event_id, game_id, position, scoring_template, planned_rounds, duration_minutes, scoring_config)
select (select id from ev29), id, 1, 'ROLE_OUTCOME', 1, 30,
       jsonb_build_object('awards', jsonb_build_object(
         'crewmate', jsonb_build_object('win', 1, 'loss', 0),
         'impostor', jsonb_build_object('win', 2, 'loss', 0)
       ))
  from games where slug = 'test-au29';
create temporary table auGame29 as select id from event_games where event_id = (select id from ev29) and position = 1;

select pg_temp.register((select id from ev29), 'ccoord', '+2348100000001');
select public.admin_create_room('test-coord29', 'COORD ROOM 01', 8,
  (select id from public.event_registrations where alias = 'ccoord'));
create temporary table croom as select id from rooms where event_id = (select id from ev29) and label = 'COORD ROOM 01';

select pg_temp.register((select id from ev29), 'ccoord2', '+2348100000002');
select public.admin_create_room('test-coord29', 'COORD ROOM 02', 8,
  (select id from public.event_registrations where alias = 'ccoord2'));
create temporary table croom2 as select id from rooms where event_id = (select id from ev29) and label = 'COORD ROOM 02';

select pg_temp.register((select id from ev29), 'cp1', '+2348100000011');
select pg_temp.register((select id from ev29), 'cp2', '+2348100000012');
insert into room_memberships (event_id, room_id, registration_id)
select (select id from ev29), (select id from croom), id from event_registrations where alias in ('cp1','cp2');

-- ==================================================================== get_player_state() coordinating

select pg_temp.as_player_session((select id from event_registrations where alias = 'cp1'));
select is(
  (select public.get_player_state()->'coordinating'),
  'null'::jsonb,
  'test 51: an ordinary player''s get_player_state() reports coordinating as null');

select pg_temp.as_player_session((select id from event_registrations where alias = 'ccoord'));
select is(
  (select public.get_player_state()->'coordinating'->>'roomLabel'),
  'COORD ROOM 01',
  'test 51: the active coordinator''s get_player_state() correctly reports their room');

-- ==================================================================== coordinator_room_state() authorization

select pg_temp.as_player_session((select id from event_registrations where alias = 'cp1'));
select throws_ok(
  $$ select public.coordinator_room_state((select id from croom)) $$,
  '42501', null,
  'test 51: an ordinary (non-coordinator) player cannot call coordinator_room_state, even for their own room');

select pg_temp.as_player_session((select id from event_registrations where alias = 'ccoord2'));
select throws_ok(
  $$ select public.coordinator_room_state((select id from croom)) $$,
  '42501', null,
  'test 51: room 2''s coordinator cannot call coordinator_room_state for room 1');

-- ==================================================================== coordinator_room_state() shape

select pg_temp.as_player_session((select id from event_registrations where alias = 'ccoord'));

select is(
  (select public.coordinator_room_state((select id from croom))->'room'->>'label'),
  'COORD ROOM 01',
  'test 51: coordinator_room_state returns the correct room label');
select is(
  (select jsonb_array_length(public.coordinator_room_state((select id from croom))->'room'->'roster')),
  2,
  'test 51: coordinator_room_state returns the correct roster size');
select is(
  (select public.coordinator_room_state((select id from croom))->'currentGame'->>'gameSlug'),
  'test-au29',
  'test 51: coordinator_room_state identifies the correct current (not-yet-completed) game');
select is(
  (select public.coordinator_room_state((select id from croom))->'currentGame'->>'roomGameStatus'),
  'PENDING',
  'test 51: a game never started for this room shows PENDING, not LIVE');
select is(
  (select public.coordinator_room_state((select id from croom))->'currentGame'->'liveRound'),
  'null'::jsonb,
  'test 51: no live round exists yet');

select public.start_room_game((select id from croom), (select id from auGame29));
select is(
  (select public.coordinator_room_state((select id from croom))->'currentGame'->>'roomGameStatus'),
  'LIVE',
  'test 51: after start_room_game, coordinator_room_state reflects LIVE status');

select public.start_round((select id from croom), (select id from auGame29));
select is(
  (select (public.coordinator_room_state((select id from croom))->'currentGame'->'liveRound'->>'roundIndex')::int),
  1,
  'test 51: coordinator_room_state reflects the live round once one is started');

create temporary table cround1 as select id from rounds where room_id=(select id from croom) and event_game_id=(select id from auGame29) and round_index=1;
select public.submit_round_result(
  (select id from cround1),
  jsonb_build_object('winningRole','crewmate','participants', jsonb_build_array(
    jsonb_build_object('registrationId',(select id from event_registrations where alias='cp1'),'participation','PARTICIPATING','role','crewmate'),
    jsonb_build_object('registrationId',(select id from event_registrations where alias='cp2'),'participation','PARTICIPATING','role','crewmate')
  )), 'idem-cround1-0001'
);
select public.complete_room_game((select id from croom), (select id from auGame29));

select is(
  (select public.coordinator_room_state((select id from croom))->'currentGame'),
  'null'::jsonb,
  'test 51: once every configured game is complete for this room, currentGame is null — nothing left to start');

select * from finish();
rollback;
