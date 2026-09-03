-- Test 39 — check_in_player() and get_player_state(), migration 0017.
--
-- Self-contained fixture event rather than the seeded recess-01: recess-01
-- is REGISTRATION per the seed and this test needs an event already in
-- CHECK_IN, with small room capacities to exercise "full" cleanly. Isolated
-- inside the same transaction/rollback as the rest of the suite.
begin;
select plan(29);

create or replace function pg_temp.as_player(p_uid uuid) returns void
language sql as $$
  insert into auth.users (id) values (p_uid);
  select set_config('request.jwt.claim.sub', p_uid::text, true);
$$;

-- ---------------------------------------------------------------------- fixture

insert into public.events (
  slug, name, status, starts_at, timezone, timezone_label,
  checkin_opens_at, checkin_closes_at, capacity
) values (
  'test-checkin', 'Test Check-In Event', 'CHECK_IN',
  now() + interval '2 hours', 'Africa/Lagos', 'WAT',
  now() - interval '30 minutes', now() + interval '2 hours', 10
);

create temporary table ev as select id from public.events where slug = 'test-checkin';

insert into public.rooms (event_id, label, position, capacity)
select id, 'ROOM A', 1, 1 from ev
union all select id, 'ROOM B', 2, 1 from ev
union all select id, 'ROOM C (unconfigured)', 3, null from ev;

-- a second event, still in REGISTRATION, to prove check-in respects event status
insert into public.events (slug, name, status, starts_at, timezone, timezone_label, capacity)
values ('test-still-registering', 'Test Not Yet', 'REGISTRATION', now() + interval '5 days', 'Africa/Lagos', 'WAT', 10);
create temporary table ev2 as select id from public.events where slug = 'test-still-registering';

-- a third event, CHECK_IN status but the window has not opened yet
insert into public.events (slug, name, status, starts_at, timezone, timezone_label, checkin_opens_at, capacity)
values ('test-not-yet-open', 'Test Not Open Yet', 'CHECK_IN', now() + interval '3 hours', 'Africa/Lagos', 'WAT', now() + interval '1 hour', 10);
create temporary table ev3 as select id from public.events where slug = 'test-not-yet-open';

-- a fourth event, CHECK_IN status but the window already closed
insert into public.events (slug, name, status, starts_at, timezone, timezone_label, checkin_closes_at, capacity)
values ('test-closed', 'Test Closed', 'CHECK_IN', now() + interval '1 hour', 'Africa/Lagos', 'WAT', now() - interval '5 minutes', 10);
create temporary table ev4 as select id from public.events where slug = 'test-closed';

create or replace function pg_temp.register(p_event uuid, p_alias text, p_phone text, p_status public.registration_status default 'REGISTERED')
returns uuid language plpgsql as $$
declare v_player_id uuid; v_reg_id uuid; v_no int;
begin
  insert into public.players (phone_e164, real_name, canonical_alias)
  values (p_phone, p_alias, p_alias) returning id into v_player_id;
  update public.event_counters set next_player_no = next_player_no + 1
   where event_id = p_event returning next_player_no - 1 into v_no;
  insert into public.event_registrations (event_id, player_id, alias, player_number, status)
  values (p_event, v_player_id, p_alias, v_no, p_status) returning id into v_reg_id;
  return v_reg_id;
end $$;

-- ------------------------------------------------------------------- rejections

select throws_like(
  $$ select public.check_in_player() $$,
  'not_authenticated:%', 'test 39: refuses with no session');

select pg_temp.as_player(gen_random_uuid());
select throws_like(
  $$ select public.check_in_player() $$,
  'not_registered:%', 'test 39: refuses a session with no registration at all');

select pg_temp.register((select id from ev2), 'NOTYET', '+2348020000001');
select pg_temp.as_player(gen_random_uuid());
update public.event_registrations set auth_user_id = (select current_setting('request.jwt.claim.sub')::uuid)
 where alias = 'NOTYET';
select throws_like(
  $$ select public.check_in_player() $$,
  'check_in_not_open:%', 'test 39: refuses when the event is not in CHECK_IN status');

select pg_temp.register((select id from ev3), 'TOOEARLY', '+2348020000002');
select pg_temp.as_player(gen_random_uuid());
update public.event_registrations set auth_user_id = (select current_setting('request.jwt.claim.sub')::uuid)
 where alias = 'TOOEARLY';
select throws_like(
  $$ select public.check_in_player() $$,
  'check_in_not_open:%', 'test 39: refuses before the configured check-in window opens');

select pg_temp.register((select id from ev4), 'TOOLATE', '+2348020000003');
select pg_temp.as_player(gen_random_uuid());
update public.event_registrations set auth_user_id = (select current_setting('request.jwt.claim.sub')::uuid)
 where alias = 'TOOLATE';
select throws_like(
  $$ select public.check_in_player() $$,
  'check_in_closed:%', 'test 39: refuses after the configured check-in window closes');

select pg_temp.register((select id from ev), 'WAITER', '+2348020000004', 'WAITLISTED');
select pg_temp.as_player(gen_random_uuid());
update public.event_registrations set auth_user_id = (select current_setting('request.jwt.claim.sub')::uuid)
 where alias = 'WAITER';
select throws_like(
  $$ select public.check_in_player() $$,
  'waitlisted:%', 'test 39: refuses a waitlisted registration');

-- --------------------------------------------------------------- successful path

select pg_temp.register((select id from ev), 'FIRST', '+2348020000010');
select pg_temp.as_player(gen_random_uuid());
update public.event_registrations set auth_user_id = (select current_setting('request.jwt.claim.sub')::uuid)
 where alias = 'FIRST';

select lives_ok($$ select public.check_in_player() $$, 'test 39: a valid check-in succeeds');

select isnt(
  (select checked_in_at from public.event_registrations where alias = 'FIRST'),
  null, 'test 39: checked_in_at is recorded');

select is(
  (select (public.check_in_player()->>'view')),
  'ROOM_ASSIGNED', 'test 39: the first player to check in gets ROOM_ASSIGNED (Room A, capacity 1)');

select is(
  (select public.check_in_player()->'room'->>'label'),
  'ROOM A', 'test 39: assigned to the first room by position');

-- ---------------------------------------------------------------- fills Room B

select pg_temp.register((select id from ev), 'SECOND', '+2348020000011');
select pg_temp.as_player(gen_random_uuid());
update public.event_registrations set auth_user_id = (select current_setting('request.jwt.claim.sub')::uuid)
 where alias = 'SECOND';
select lives_ok($$ select public.check_in_player() $$, 'test 39: a second check-in succeeds');
select is(
  (select public.check_in_player()->'room'->>'label'),
  'ROOM B', 'test 39: Room A is full, so the second player goes to Room B');

-- ------------------------------------------------------ third player: no room left

select pg_temp.register((select id from ev), 'THIRD', '+2348020000012');
select pg_temp.as_player(gen_random_uuid());
update public.event_registrations set auth_user_id = (select current_setting('request.jwt.claim.sub')::uuid)
 where alias = 'THIRD';
select lives_ok($$ select public.check_in_player() $$, 'test 39: check-in still succeeds when every room is full');
select is(
  (select (public.check_in_player()->>'view')),
  'CHECKED_IN_WAITING', 'test 39: WAITING_FOR_ROOM is checked in with no room — CHECKED_IN_WAITING view');
select is(
  (select public.check_in_player() ? 'room'),
  false, 'test 39: the room key is absent entirely when unassigned, not present-with-null');
select is(
  (select count(*)::int from public.room_memberships rm
     join public.event_registrations r on r.id = rm.registration_id
    where r.alias in ('FIRST','SECOND','THIRD') and rm.left_at is null),
  2, 'test 39: only two memberships exist — Room C was never used despite being iterated');

-- room C has no configured capacity and must never be silently unlimited
select is(
  (select count(*)::int from public.room_memberships rm
     join public.rooms ro on ro.id = rm.room_id
    where ro.label = 'ROOM C (unconfigured)'),
  0, 'test 39: a room with null capacity never receives a membership');

-- ------------------------------------------------------------------ idempotency

-- Re-establish FIRST's own session — the last few as_player() calls moved
-- request.jwt.claim.sub on to SECOND and THIRD's sessions in turn.
select set_config('request.jwt.claim.sub', (select auth_user_id::text from public.event_registrations where alias = 'FIRST'), true);

select is(
  (select count(*)::int from public.room_memberships rm
     join public.event_registrations r on r.id = rm.registration_id
    where r.alias = 'FIRST' and rm.left_at is null),
  1, 'test 39: exactly one active membership before the retry');

select lives_ok($$ select public.check_in_player() $$, 'test 39: re-checking in an already-checked-in player does not raise');

select is(
  (select count(*)::int from public.room_memberships rm
     join public.event_registrations r on r.id = rm.registration_id
    where r.alias = 'FIRST' and rm.left_at is null),
  1, 'test 39: the retry did not create a second membership');

select is(
  (select public.check_in_player()->'room'->>'label'),
  'ROOM A', 'test 39: the retry still reports the original room');

-- ------------------------------------------------------------------ get_player_state

select pg_temp.register((select id from ev2), 'COUNTER', '+2348020000020');
select pg_temp.as_player(gen_random_uuid());
update public.event_registrations set auth_user_id = (select current_setting('request.jwt.claim.sub')::uuid)
 where alias = 'COUNTER';
select is(
  (select public.get_player_state()->>'view'),
  'PASS_COUNTDOWN', 'test 39: a REGISTERED player before CHECK_IN gets PASS_COUNTDOWN');
select is(
  (select public.get_player_state()->'event'->>'whatsappGroupUrl' is null),
  true, 'test 39: PASS_COUNTDOWN payload has no whatsapp url when the event has none configured');
select is(
  (select jsonb_typeof(public.get_player_state()->'games')),
  'array', 'test 39: PASS_COUNTDOWN includes a games array');

select pg_temp.register((select id from ev4), 'CLOSEDPLAYER', '+2348020000021');
select pg_temp.as_player(gen_random_uuid());
update public.event_registrations set auth_user_id = (select current_setting('request.jwt.claim.sub')::uuid)
 where alias = 'CLOSEDPLAYER';
select is(
  (select public.get_player_state()->>'view'),
  'CHECK_IN_OPEN', 'test 39: get_player_state reports CHECK_IN_OPEN for an event in CHECK_IN before this player has checked in');
select is(
  (select (public.get_player_state()->'checkIn'->>'available')::boolean),
  false, 'test 39: checkIn.available is false once the configured window has closed');

select pg_temp.as_player(gen_random_uuid());
select is(
  public.get_player_state(), null, 'test 39: a session with no registration gets a null state, not an error');

-- ---------------------------------------------------------------- room privacy

select pg_temp.as_player(gen_random_uuid());
update public.event_registrations set auth_user_id = (select current_setting('request.jwt.claim.sub')::uuid)
 where alias = 'CLOSEDPLAYER';
select is(
  (select public.get_player_state()->'event'->>'whatsappGroupUrl' is null),
  true, 'test 39: whatsappGroupUrl is absent on the CHECK_IN_OPEN view, not just PASS_COUNTDOWN');

-- re-check as the FIRST player (ROOM_ASSIGNED) that no room whatsapp/url leaks
-- and that the room's own url is not part of this payload at all yet
select pg_temp.as_player(gen_random_uuid());
update public.event_registrations set auth_user_id = (select current_setting('request.jwt.claim.sub')::uuid)
 where alias = 'FIRST';
select is(
  (select public.get_player_state()->'room' ? 'whatsappGroupUrl'),
  false, 'test 39: the room payload never includes a whatsapp url in this phase');

select * from finish();
rollback;
