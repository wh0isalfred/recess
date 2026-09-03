-- Test 40 — migration 0018: Screen 09's real ROOM_ASSIGNED payload, the
-- staff-authorization helper, and the first admin RPCs.
begin;
select plan(35);

create or replace function pg_temp.as_player(p_uid uuid) returns void
language sql as $$
  insert into auth.users (id) values (p_uid);
  select set_config('request.jwt.claim.sub', p_uid::text, true);
$$;

create or replace function pg_temp.as_staff(p_uid uuid, p_role public.staff_role) returns void
language sql as $$
  insert into auth.users (id) values (p_uid);
  insert into public.staff_profiles (user_id, name, role) values (p_uid, 'Test Staff', p_role);
  select set_config('request.jwt.claim.sub', p_uid::text, true);
$$;

-- ---------------------------------------------------------------------- fixture

insert into public.events (
  slug, name, status, starts_at, timezone, timezone_label,
  checkin_opens_at, checkin_closes_at, capacity
) values (
  'test-admin18', 'Test Admin Event', 'CHECK_IN',
  now() + interval '2 hours', 'Africa/Lagos', 'WAT',
  now() - interval '30 minutes', now() + interval '2 hours', 10
);
create temporary table ev as select id from public.events where slug = 'test-admin18';

insert into public.rooms (event_id, label, position, capacity)
select id, 'ROOM 01', 1, 2 from ev
union all select id, 'ROOM 02', 2, null from ev;

insert into public.games (slug, name, platform, scoring_template, status, artwork_url)
values ('test-game18', 'Test Game', 'BROWSER', 'PLACEMENT', 'ACTIVE', '/games/test-game18.webp');
insert into public.event_games (event_id, game_id, position, scoring_template, planned_rounds)
select ev.id, g.id, 1, 'PLACEMENT', 1 from ev, public.games g where g.slug = 'test-game18';

update public.rooms set whatsapp_group_url = 'https://chat.whatsapp.com/AbCdEfGhIjKl'
 where event_id = (select id from ev) and label = 'ROOM 01';

create or replace function pg_temp.register(p_alias text, p_phone text) returns uuid
language plpgsql as $$
declare v_player_id uuid; v_reg_id uuid; v_no int;
begin
  insert into public.players (phone_e164, real_name, canonical_alias) values (p_phone, p_alias, p_alias) returning id into v_player_id;
  update public.event_counters set next_player_no = next_player_no + 1
   where event_id = (select id from ev) returning next_player_no - 1 into v_no;
  insert into public.event_registrations (event_id, player_id, alias, player_number, status)
  values ((select id from ev), v_player_id, p_alias, v_no, 'REGISTERED') returning id into v_reg_id;
  return v_reg_id;
end $$;

-- ------------------------------------------------------------- Screen 09 payload

select pg_temp.register('ROOMIE1', '+2348040000001');
select pg_temp.as_player(gen_random_uuid());
update public.event_registrations set auth_user_id = (select current_setting('request.jwt.claim.sub')::uuid)
 where alias = 'ROOMIE1';
select lives_ok($$ select public.check_in_player() $$, 'test 40: ROOMIE1 checks in and is assigned Room 01');

select pg_temp.register('ROOMIE2', '+2348040000002');
select pg_temp.as_player(gen_random_uuid());
update public.event_registrations set auth_user_id = (select current_setting('request.jwt.claim.sub')::uuid)
 where alias = 'ROOMIE2';
select lives_ok($$ select public.check_in_player() $$, 'test 40: ROOMIE2 checks in and fills Room 01');

-- back to ROOMIE1's session to read their own state
select set_config('request.jwt.claim.sub', (select auth_user_id::text from public.event_registrations where alias = 'ROOMIE1'), true);

select is(
  (select public.get_player_state()->'room'->>'label'), 'ROOM 01', 'test 40: room label is real');
select is(
  (select (public.get_player_state()->'room'->>'capacity')::int), 2, 'test 40: room capacity is real');
select is(
  (select (public.get_player_state()->'room'->>'occupancy')::int), 2, 'test 40: room occupancy is real (both roommates counted)');
select is(
  (select public.get_player_state()->'room'->>'whatsappGroupUrl'), 'https://chat.whatsapp.com/AbCdEfGhIjKl',
  'test 40: room whatsapp url is the ROOM''s, not the event''s');
select is(
  (select jsonb_array_length(public.get_player_state()->'room'->'roster')), 2, 'test 40: roster has both roommates');
select ok(
  (select public.get_player_state()->'room'->'roster' @> '[{"alias":"ROOMIE1"}]'::jsonb),
  'test 40: the caller''s own alias is in their own roster');
select ok(
  (select public.get_player_state()->'room'->'roster' @> '[{"alias":"ROOMIE2"}]'::jsonb),
  'test 40: the roommate''s alias is in the roster');
select is(
  (select jsonb_typeof((public.get_player_state()->'room'->'roster'->0) - 'alias')), 'object',
  'test 40: a roster entry has other keys besides alias (structural sanity)');
select is(
  (select public.get_player_state()->'room'->'roster'->0 ? 'phone'), false,
  'test 40: no phone number anywhere in a roster entry');
select is(
  (select public.get_player_state()->'upFirstGame'->>'slug'), 'test-game18',
  'test 40: upFirstGame is the event''s configured game');
select is(
  (select public.get_player_state()->'upFirstGame'->>'artworkUrl'), '/games/test-game18.webp',
  'test 40: upFirstGame carries the artwork path');

-- a player in Room 02 must not see Room 01's roster or whatsapp url
select pg_temp.register('OUTSIDER', '+2348040000003');
insert into public.room_memberships (event_id, room_id, registration_id)
select (select id from ev), (select id from rooms where event_id=(select id from ev) and label='ROOM 02'),
       (select id from event_registrations where alias='OUTSIDER');
update public.event_registrations set checked_in_at = now() where alias = 'OUTSIDER';
select pg_temp.as_player(gen_random_uuid());
update public.event_registrations set auth_user_id = (select current_setting('request.jwt.claim.sub')::uuid)
 where alias = 'OUTSIDER';
select is(
  (select public.get_player_state()->'room'->>'label'), 'ROOM 02', 'test 40: OUTSIDER correctly sees their own room');
select is(
  (select public.get_player_state()->'room'->'roster' @> '[{"alias":"ROOMIE1"}]'::jsonb), false,
  'test 40: OUTSIDER cannot see Room 01''s roster');

-- ----------------------------------------------------------------- authorization

select pg_temp.as_player(gen_random_uuid());
select throws_like(
  $$ select public.admin_event_overview('test-admin18') $$,
  'not_authorized:%', 'test 40: a plain player session is refused admin_event_overview');

select pg_temp.as_staff(gen_random_uuid(), 'COORDINATOR');
select throws_like(
  $$ select public.admin_upsert_room('test-admin18', null, 'ROOM X', 10, null) $$,
  'not_authorized:%', 'test 40: a COORDINATOR (not EVENT_ADMIN/SUPER_ADMIN) is refused room CRUD');

select pg_temp.as_staff(gen_random_uuid(), 'EVENT_ADMIN');

-- --------------------------------------------------------------- event overview

select is(
  (select (public.admin_event_overview('test-admin18')->'counts'->>'checkedIn')::int), 3,
  'test 40: admin_event_overview counts checked-in correctly (ROOMIE1, ROOMIE2, OUTSIDER)');
select is(
  (select (public.admin_event_overview('test-admin18')->'counts'->>'assigned')::int), 3,
  'test 40: admin_event_overview counts assigned correctly');

-- --------------------------------------------------------------------- room CRUD

select throws_like(
  $$ select public.admin_upsert_room('test-admin18', null, '', 10, null) $$,
  'invalid_label:%', 'test 40: an empty label is refused');
select throws_like(
  $$ select public.admin_upsert_room('test-admin18', null, 'Bad WA', 10, 'https://evil.example.com/x') $$,
  'invalid_whatsapp_url:%', 'test 40: a non-WhatsApp url is refused');

select lives_ok(
  $$ select public.admin_upsert_room('test-admin18', null, 'ROOM 03', 5, null) $$,
  'test 40: creating a new room succeeds');
select is(
  (select position from rooms where event_id=(select id from ev) and label='ROOM 03'), 3,
  'test 40: the new room gets the next sequential position');

select lives_ok(
  $$ select public.admin_upsert_room('test-admin18', (select id from rooms where event_id=(select id from ev) and label='ROOM 03'), 'ROOM 03', 8, null) $$,
  'test 40: updating an existing room succeeds');
select is(
  (select capacity from rooms where event_id=(select id from ev) and label='ROOM 03'), 8,
  'test 40: the room update actually changed capacity');

-- ----------------------------------------------------------------- coordinator

select lives_ok(
  $$ select public.admin_assign_coordinator('test-admin18', (select id from rooms where event_id=(select id from ev) and label='ROOM 01'),
       (select user_id from staff_profiles limit 1)) $$,
  'test 40: assigning a coordinator succeeds');
select isnt(
  (select public.admin_list_rooms('test-admin18')->'rooms'->0->'coordinator'), null,
  'test 40: admin_list_rooms reflects the assigned coordinator');

-- ------------------------------------------------------------------- room members

select is(
  (select jsonb_array_length(public.admin_room_members(
     (select id from rooms where event_id=(select id from ev) and label='ROOM 01')
   ))), 2, 'test 40: admin_room_members lists both Room 01 occupants');

-- --------------------------------------------------------- assign waiting players

select pg_temp.register('WAITER1', '+2348040000004');
update public.event_registrations set checked_in_at = now() where alias = 'WAITER1';
select pg_temp.register('WAITER2', '+2348040000005');
update public.event_registrations set checked_in_at = now() where alias = 'WAITER2';

-- ROOM 03 has capacity 8 and zero occupants — exactly one seat's worth of
-- headroom is irrelevant here; both waiters fit.
select is(
  (select (public.admin_assign_waiting_players('test-admin18')->>'assigned')::int), 2,
  'test 40: both waiting players are assigned into the room with headroom');

select lives_ok(
  $$ select public.admin_assign_waiting_players('test-admin18') $$,
  'test 40: running the assignment again with nobody waiting does not raise');
select is(
  (select (public.admin_assign_waiting_players('test-admin18')->>'assigned')::int), 0,
  'test 40: the idempotent re-run assigns nobody a second time');
select is(
  (select count(*)::int from room_memberships rm join event_registrations er on er.id=rm.registration_id
    where er.alias = 'WAITER1' and rm.left_at is null), 1,
  'test 40: WAITER1 has exactly one active membership after the re-run, not two');

-- --------------------------------------------------------------- open check-in

select pg_temp.as_player(gen_random_uuid());
select throws_like(
  $$ select public.admin_open_check_in('test-admin18') $$,
  'not_authorized:%', 'test 40: a plain player cannot open check-in');

select pg_temp.as_staff(gen_random_uuid(), 'EVENT_ADMIN');
insert into public.events (slug, name, status, starts_at, timezone, timezone_label, checkin_opens_at, checkin_closes_at, capacity)
values ('test-openci18', 'Test Open CI', 'REGISTRATION', now() + interval '1 day', 'Africa/Lagos', 'WAT',
        now() - interval '5 minutes', now() + interval '3 hours', 10);
insert into public.rooms (event_id, label, position, capacity)
select id, 'ONLY ROOM', 1, 10 from events where slug = 'test-openci18';
select lives_ok(
  $$ select public.admin_open_check_in('test-openci18') $$,
  'test 40: an EVENT_ADMIN can open check-in via the real lifecycle function');
select is(
  (select status from events where slug = 'test-openci18'), 'CHECK_IN'::event_status,
  'test 40: the event actually transitioned, through transition_event() itself');

select * from finish();
rollback;
