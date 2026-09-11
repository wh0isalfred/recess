-- Test 53 — Coordinator standings hotfix (migration 0031).
begin;
select plan(10);

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

select pg_temp.as_staff(gen_random_uuid(), 'SUPER_ADMIN');

insert into public.events (slug, name, status, starts_at, timezone, timezone_label, capacity)
values ('test-standhotfix31', 'Standings Hotfix Event', 'LIVE', now() - interval '1 hour', 'Africa/Lagos', 'WAT', 30);
create temporary table ev31 as select id from public.events where slug = 'test-standhotfix31';

insert into public.games (slug, name, platform, scoring_template, status, artwork_url, default_round_count)
values ('test-au31', 'Test Among Us 31', 'INSTALL', 'ROLE_OUTCOME', 'ACTIVE', '/games/test-au31.webp', 1);
insert into event_games (event_id, game_id, position, scoring_template, planned_rounds, scoring_config)
select (select id from ev31), id, 1, 'ROLE_OUTCOME', 1,
       jsonb_build_object('awards', jsonb_build_object(
         'crewmate', jsonb_build_object('win', 1, 'loss', 0),
         'impostor', jsonb_build_object('win', 2, 'loss', 0)
       ))
  from games where slug = 'test-au31';
create temporary table auGame31 as select id from event_games where event_id = (select id from ev31) and position = 1;

select pg_temp.register((select id from ev31), 'scoord', '+2348120000001');
select public.admin_create_room('test-standhotfix31', 'STAND ROOM 01', 8,
  (select id from public.event_registrations where alias = 'scoord'));
create temporary table sroom as select id from rooms where event_id = (select id from ev31) and label = 'STAND ROOM 01';

select pg_temp.register((select id from ev31), 'scoord2', '+2348120000002');
select public.admin_create_room('test-standhotfix31', 'STAND ROOM 02', 8,
  (select id from public.event_registrations where alias = 'scoord2'));
create temporary table sroom2 as select id from rooms where event_id = (select id from ev31) and label = 'STAND ROOM 02';

select pg_temp.register((select id from ev31), 'sp1', '+2348120000011');
select pg_temp.register((select id from ev31), 'sp2', '+2348120000012');
insert into room_memberships (event_id, room_id, registration_id)
select (select id from ev31), (select id from sroom), id from event_registrations where alias in ('sp1','sp2');

select public.start_room_game((select id from sroom), (select id from auGame31));
select public.start_round((select id from sroom), (select id from auGame31));
create temporary table sround1 as select id from rounds where room_id=(select id from sroom) and event_game_id=(select id from auGame31) and round_index=1;
select public.submit_round_result(
  (select id from sround1),
  jsonb_build_object('winningRole','crewmate','participants', jsonb_build_array(
    jsonb_build_object('registrationId',(select id from event_registrations where alias='sp1'),'participation','PARTICIPATING','role','crewmate'),
    jsonb_build_object('registrationId',(select id from event_registrations where alias='sp2'),'participation','PARTICIPATING','role','impostor')
  )), 'idem-sround1-0001'
);
select public.complete_room_game((select id from sroom), (select id from auGame31));

create temporary table pre_txn_count as select count(*) as n from point_transactions where voided_at is null;

select lives_ok(
  $$ select public.room_standings((select id from sroom)) $$,
  'test 53: event admin can still call room_standings()');

select pg_temp.as_player_session((select id from event_registrations where alias = 'sp1'));
select throws_like(
  $$ select public.room_standings((select id from sroom)) $$,
  'not_authorized%',
  'test 53: an ordinary player still cannot call room_standings() — the admin-only contract is unchanged');

select pg_temp.as_player_session((select id from event_registrations where alias = 'scoord'));
select lives_ok(
  $$ select public.coordinator_room_standings((select id from sroom)) $$,
  'test 53: the active coordinator can call coordinator_room_standings() for their own room');

select throws_like(
  $$ select public.coordinator_room_standings((select id from sroom2)) $$,
  'not_authorized%',
  'test 53: a coordinator cannot call coordinator_room_standings() for a different room');

select pg_temp.as_player_session((select id from event_registrations where alias = 'sp1'));
select throws_like(
  $$ select public.coordinator_room_standings((select id from sroom)) $$,
  'not_authorized%',
  'test 53: an unrelated registered player (not staff, not this room''s coordinator) cannot call coordinator_room_standings()');

select set_config('request.jwt.claim.sub', '', true);
select throws_ok(
  $$ select public.coordinator_room_standings((select id from sroom)) $$,
  '42501', null,
  'test 53: an unauthenticated caller is refused');

select pg_temp.as_staff(gen_random_uuid(), 'SUPER_ADMIN');
create temporary table admin_view as select public.room_standings((select id from sroom)) as standings;

select pg_temp.as_player_session((select id from event_registrations where alias = 'scoord'));
select is(
  (select public.coordinator_room_standings((select id from sroom))),
  (select standings from admin_view),
  'test 53: coordinator_room_standings() returns exactly the same standings as room_standings() for the same room');

select is(
  (select (jsonb_path_query_first(public.coordinator_room_standings((select id from sroom)), '$[*] ? (@.alias == "sp2")')->>'qualifies')),
  'true',
  'test 53: qualification (top-2, competition ranking) is unchanged — sp2 qualifies');
select is(
  (select (jsonb_path_query_first(public.coordinator_room_standings((select id from sroom)), '$[*] ? (@.alias == "sp1")')->>'qualifies')),
  'true',
  'test 53: sp1 also qualifies — a 2-player room''s both players are within the top-2 boundary, unchanged rule');

select is(
  (select count(*) from point_transactions where voided_at is null),
  (select n from pre_txn_count),
  'test 53: calling coordinator_room_standings() (repeatedly, across every check above) created or voided zero ledger rows');

select * from finish();
rollback;
