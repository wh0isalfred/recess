-- Test 43 — Phase 6.5: Night Engine Alignment (migration 0021).
begin;
select plan(46);

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

-- Registers directly (bypassing register_player()) with a fake auth_user_id
-- so the row is coordinator-eligible without a real session; tests that
-- need the registration to actually check in separately reassign
-- auth_user_id to a real as_player() session, same pattern 11's fixture uses.
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

insert into public.events (
  slug, name, status, starts_at, timezone, timezone_label,
  checkin_opens_at, checkin_closes_at, capacity
) values (
  'test-night21', 'Test Night Engine Event', 'CHECK_IN',
  now() + interval '2 hours', 'Africa/Lagos', 'WAT',
  now() - interval '30 minutes', now() + interval '2 hours', 60
);
create temporary table ev21 as select id from public.events where slug = 'test-night21';

insert into public.events (slug, name, status, starts_at, timezone, timezone_label, capacity)
values ('test-night21-other', 'Other Event', 'REGISTRATION', now() + interval '10 days', 'Africa/Lagos', 'WAT', 30);
create temporary table ev21_other as select id from public.events where slug = 'test-night21-other';

insert into public.games (slug, name, platform, scoring_template, status, artwork_url)
values ('test-game21', 'Test Game 21', 'BROWSER', 'PLACEMENT', 'ACTIVE', '/games/test-game21.webp');
insert into public.games (slug, name, platform, scoring_template, status, artwork_url)
values ('test-game21b', 'Test Game 21b', 'BROWSER', 'PLACEMENT', 'ACTIVE', '/games/test-game21b.webp');

insert into public.event_games (event_id, game_id, position, scoring_template, planned_rounds, duration_minutes)
select ev21.id, g.id, 1, 'PLACEMENT', 1, 30 from ev21, public.games g where g.slug = 'test-game21';
insert into public.event_games (event_id, game_id, position, scoring_template, planned_rounds)
select ev21.id, g.id, 2, 'PLACEMENT', 1 from ev21, public.games g where g.slug = 'test-game21b';

select pg_temp.as_staff(gen_random_uuid(), 'EVENT_ADMIN');

-- ==================================================================== ROOM / CAPACITY

select pg_temp.register((select id from ev21), 'cap1cand', '+2348050000001');
select lives_ok(
  $$ select public.admin_create_room('test-night21', 'CAP 1 ROOM 2', 1,
       (select id from public.event_registrations where alias = 'cap1cand')) $$,
  'test 43: capacity 1 accepted where valid');

select pg_temp.register((select id from ev21), 'cap15cand', '+2348050000002');
select lives_ok(
  $$ select public.admin_create_room('test-night21', 'CAP 15 ROOM', 15,
       (select id from public.event_registrations where alias = 'cap15cand')) $$,
  'test 43: capacity 15 accepted');

select pg_temp.register((select id from ev21), 'cap16cand', '+2348050000003');
select throws_like(
  $$ select public.admin_create_room('test-night21', 'CAP 16 ROOM', 16,
       (select id from public.event_registrations where alias = 'cap16cand')) $$,
  'invalid_capacity%',
  'test 43: capacity 16 rejected');

select throws_like(
  $$ select public.admin_create_room('test-night21', 'CAP 0 ROOM', 0,
       (select id from public.event_registrations where alias = 'cap16cand')) $$,
  'invalid_capacity%',
  'test 43: capacity 0 rejected');

select pg_temp.register((select id from ev21), 'nocoordcand', '+2348050000004');
select throws_like(
  $$ select public.admin_create_room('test-night21', 'NO COORD ROOM', 5, null) $$,
  'coordinator_required%',
  'test 43: room creation without coordinator rejected');

select pg_temp.register((select id from ev21_other), 'wrongevcand', '+2348050000005');
select throws_like(
  $$ select public.admin_create_room('test-night21', 'WRONG EVENT ROOM', 5,
       (select id from public.event_registrations where alias = 'wrongevcand')) $$,
  'coordinator_wrong_event%',
  'test 43: coordinator from wrong event rejected');

insert into public.players (phone_e164, real_name, canonical_alias) values ('+2348050000006', 'waitlistcand', 'waitlistcand');
insert into public.event_registrations (event_id, player_id, alias, player_number, status, auth_user_id)
select (select id from ev21), (select id from players where phone_e164='+2348050000006'), 'waitlistcand', 9001, 'WAITLISTED', gen_random_uuid();
select throws_like(
  $$ select public.admin_create_room('test-night21', 'WAITLIST ROOM', 5,
       (select id from public.event_registrations where alias = 'waitlistcand')) $$,
  'coordinator_waitlisted%',
  'test 43: waitlisted candidate rejected');

insert into public.players (phone_e164, real_name, canonical_alias) values ('+2348050000007', 'cancelledcand', 'cancelledcand');
insert into public.event_registrations (event_id, player_id, alias, player_number, status, auth_user_id)
select (select id from ev21), (select id from players where phone_e164='+2348050000007'), 'cancelledcand', 9002, 'CANCELLED', gen_random_uuid();
select throws_like(
  $$ select public.admin_create_room('test-night21', 'CANCELLED ROOM', 5,
       (select id from public.event_registrations where alias = 'cancelledcand')) $$,
  'coordinator_cancelled%',
  'test 43: cancelled candidate rejected');

select pg_temp.register((select id from ev21), 'checkedincand', '+2348050000008');
update public.event_registrations set checked_in_at = now() where alias = 'checkedincand';
select throws_like(
  $$ select public.admin_create_room('test-night21', 'CHECKEDIN ROOM', 5,
       (select id from public.event_registrations where alias = 'checkedincand')) $$,
  'coordinator_checked_in%',
  'test 43: checked-in candidate rejected');

select pg_temp.register((select id from ev21), 'doublecoordcand', '+2348050000009');
select public.admin_create_room('test-night21', 'FIRST ROOM FOR DBL', 5,
  (select id from public.event_registrations where alias = 'doublecoordcand'));
select throws_like(
  $$ select public.admin_create_room('test-night21', 'SECOND ROOM FOR DBL', 5,
       (select id from public.event_registrations where alias = 'doublecoordcand')) $$,
  'coordinator_already_assigned%',
  'test 43: coordinator already assigned elsewhere rejected');

-- ==================================================================== SEAT RESERVATION

insert into public.events (
  slug, name, status, starts_at, timezone, timezone_label,
  checkin_opens_at, checkin_closes_at, capacity
) values (
  'test-night21-seats', 'Seat Reservation Event', 'CHECK_IN',
  now() + interval '2 hours', 'Africa/Lagos', 'WAT',
  now() - interval '30 minutes', now() + interval '2 hours', 30
);
create temporary table ev21s as select id from public.events where slug = 'test-night21-seats';

select pg_temp.register((select id from ev21s), 'seatcoord', '+2348051000001');
select public.admin_create_room('test-night21-seats', 'SEAT ROOM', 15,
  (select id from public.event_registrations where alias = 'seatcoord'));
create temporary table seatroom as select id from public.rooms where event_id = (select id from ev21s) and label = 'SEAT ROOM';

-- 14 ordinary players check in (real check_in_player() calls as real sessions).
do $$
declare i int; v_reg_id uuid; v_phone text; v_alias text; v_uid uuid;
begin
  for i in 1..14 loop
    v_alias := 'seatp' || i;
    v_phone := '+23480520000' || lpad(i::text, 2, '0');
    v_reg_id := pg_temp.register((select id from ev21s), v_alias, v_phone);
    v_uid := gen_random_uuid();
    insert into auth.users (id) values (v_uid);
    update public.event_registrations set auth_user_id = v_uid where id = v_reg_id;
    perform set_config('request.jwt.claim.sub', v_uid::text, true);
    perform public.check_in_player();
  end loop;
end $$;

select is(
  (select count(*) from public.room_memberships where room_id = (select id from seatroom) and left_at is null),
  14::bigint,
  'test 43: 14 ordinary players fit in a capacity-15 room with an unfulfilled coordinator reservation');

-- 15th ordinary player must wait — the reserved seat is not given away.
select pg_temp.register((select id from ev21s), 'seatp15', '+2348052000015');
select pg_temp.as_player(gen_random_uuid());
update public.event_registrations set auth_user_id = (select current_setting('request.jwt.claim.sub')::uuid)
 where alias = 'seatp15';
select public.check_in_player();
select is(
  (select count(*) from public.room_memberships where room_id = (select id from seatroom) and left_at is null),
  14::bigint,
  'test 43: fifteenth ordinary player does not take the reserved coordinator seat');
select is(
  (select public.get_player_state()->>'view'),
  'CHECKED_IN_WAITING',
  'test 43: the fifteenth ordinary player is genuinely waiting, not errored');

-- The coordinator checks in and becomes member 15, assigned directly.
select pg_temp.as_player(gen_random_uuid());
update public.event_registrations set auth_user_id = (select current_setting('request.jwt.claim.sub')::uuid)
 where alias = 'seatcoord';
select public.check_in_player();
select is(
  (select count(*) from public.room_memberships where room_id = (select id from seatroom) and left_at is null),
  15::bigint,
  'test 43: the coordinator checking in becomes member 15');
select is(
  (select rm.registration_id from public.room_memberships rm
    where rm.room_id = (select id from seatroom) and rm.left_at is null
      and rm.registration_id = (select id from event_registrations where alias = 'seatcoord')),
  (select id from event_registrations where alias = 'seatcoord'),
  'test 43: the coordinator is assigned directly to their own room (not queued behind ordinary fill)');

-- Idempotent double check-in.
select public.check_in_player();
select is(
  (select count(*) from public.room_memberships where room_id = (select id from seatroom) and registration_id = (select id from event_registrations where alias = 'seatcoord') and left_at is null),
  1::bigint,
  'test 43: coordinator double check-in is idempotent (still exactly one active membership)');

-- ==================================================================== SEQUENTIAL FILL

select pg_temp.as_staff(gen_random_uuid(), 'EVENT_ADMIN');

insert into public.events (
  slug, name, status, starts_at, timezone, timezone_label,
  checkin_opens_at, checkin_closes_at, capacity
) values (
  'test-night21-seq', 'Sequential Fill Event', 'CHECK_IN',
  now() + interval '2 hours', 'Africa/Lagos', 'WAT',
  now() - interval '30 minutes', now() + interval '2 hours', 30
);
create temporary table ev21q as select id from public.events where slug = 'test-night21-seq';

select pg_temp.register((select id from ev21q), 'seqcoord1', '+2348053000001');
select pg_temp.register((select id from ev21q), 'seqcoord2', '+2348053000002');
select public.admin_create_room('test-night21-seq', 'SEQ ROOM 01', 1,
  (select id from public.event_registrations where alias = 'seqcoord1'));
select public.admin_create_room('test-night21-seq', 'SEQ ROOM 02', 15,
  (select id from public.event_registrations where alias = 'seqcoord2'));

-- Room 01 capacity 1, fully reserved by its own coordinator (unchecked-in).
-- An ordinary player must go to Room 02, never stealing Room 01's only seat.
select pg_temp.register((select id from ev21q), 'seqp1', '+2348053000003');
select pg_temp.as_player(gen_random_uuid());
update public.event_registrations set auth_user_id = (select current_setting('request.jwt.claim.sub')::uuid)
 where alias = 'seqp1';
select public.check_in_player();
select is(
  (select ro.label from room_memberships rm join rooms ro on ro.id = rm.room_id
    where rm.registration_id = (select id from event_registrations where alias = 'seqp1') and rm.left_at is null),
  'SEQ ROOM 02',
  'test 43: Room 01 fully reserved -> ordinary player correctly lands in Room 02, not stuck waiting for Room 01');

-- Now let seqcoord1 check in, taking Room 01's only (reserved) seat.
select pg_temp.as_player(gen_random_uuid());
update public.event_registrations set auth_user_id = (select current_setting('request.jwt.claim.sub')::uuid)
 where alias = 'seqcoord1';
select public.check_in_player();
select is(
  (select ro.label from room_memberships rm join rooms ro on ro.id = rm.room_id
    where rm.registration_id = (select id from event_registrations where alias = 'seqcoord1') and rm.left_at is null),
  'SEQ ROOM 01',
  'test 43: reservation-adjusted Room 01 (capacity 1, coordinator seat) is filled by its own coordinator, confirming it was effectively full before');

select is(
  (select count(*) from event_registrations er
    where er.event_id = (select id from ev21q)
      and (select count(*) from room_memberships rm where rm.registration_id = er.id and rm.left_at is null) > 1),
  0::bigint,
  'test 43: nobody in this event has two active memberships');

select ok(
  not exists (
    select 1 from rooms ro
     where ro.event_id = (select id from ev21q)
       and (select count(*) from room_memberships rm where rm.room_id = ro.id and rm.left_at is null) > ro.capacity
  ),
  'test 43: no room exceeds its configured capacity');

-- ==================================================================== WAITING

select pg_temp.as_staff(gen_random_uuid(), 'EVENT_ADMIN');

insert into public.events (
  slug, name, status, starts_at, timezone, timezone_label,
  checkin_opens_at, checkin_closes_at, capacity
) values (
  'test-night21-wait', 'Waiting Event', 'CHECK_IN',
  now() + interval '2 hours', 'Africa/Lagos', 'WAT',
  now() - interval '30 minutes', now() + interval '2 hours', 30
);
create temporary table ev21w as select id from public.events where slug = 'test-night21-wait';

select pg_temp.register((select id from ev21w), 'waitcoord1', '+2348054000001');
select public.admin_create_room('test-night21-wait', 'WAIT ROOM 01', 1,
  (select id from public.event_registrations where alias = 'waitcoord1'));
-- Room full (coordinator's own reserved+occupied seat via check-in below).
select pg_temp.as_player(gen_random_uuid());
update public.event_registrations set auth_user_id = (select current_setting('request.jwt.claim.sub')::uuid)
 where alias = 'waitcoord1';
select public.check_in_player();

select pg_temp.register((select id from ev21w), 'waitp1', '+2348054000002');
select pg_temp.as_player(gen_random_uuid());
update public.event_registrations set auth_user_id = (select current_setting('request.jwt.claim.sub')::uuid)
 where alias = 'waitp1';
select public.check_in_player();
select is(
  (select public.get_player_state()->>'view'),
  'CHECKED_IN_WAITING',
  'test 43: when all rooms are full, a new check-in correctly becomes CHECKED_IN_WAITING');

select pg_temp.register((select id from ev21w), 'waitcoord2', '+2348054000003');
select pg_temp.as_staff(gen_random_uuid(), 'EVENT_ADMIN');
select public.admin_create_room('test-night21-wait', 'WAIT ROOM 02', 5,
  (select id from public.event_registrations where alias = 'waitcoord2'));
select is(
  (select ro.label from room_memberships rm join rooms ro on ro.id = rm.room_id
    where rm.registration_id = (select id from event_registrations where alias = 'waitp1') and rm.left_at is null),
  'WAIT ROOM 02',
  'test 43: creating another staffed room assigns the waiting player in check-in order (via admin_create_room''s own call to admin_assign_waiting_players)');

select pg_temp.register((select id from ev21w), 'waitp2', '+2348054000004');
select pg_temp.as_player(gen_random_uuid());
update public.event_registrations set auth_user_id = (select current_setting('request.jwt.claim.sub')::uuid)
 where alias = 'waitp2';
select public.check_in_player();
select pg_temp.as_staff(gen_random_uuid(), 'EVENT_ADMIN');
select public.admin_upsert_room('test-night21-wait',
  (select id from rooms where event_id = (select id from ev21w) and label = 'WAIT ROOM 02'),
  'WAIT ROOM 02', 6, null);
select is(
  (select ro.label from room_memberships rm join rooms ro on ro.id = rm.room_id
    where rm.registration_id = (select id from event_registrations where alias = 'waitp2') and rm.left_at is null),
  'WAIT ROOM 02',
  'test 43: increasing a room''s capacity assigns a waiting player in check-in order');

select lives_ok(
  $$ select public.admin_assign_waiting_players('test-night21-wait') $$,
  'test 43: retrying the allocation operation does not error');
select is(
  (select count(*) from event_registrations er
    where er.event_id = (select id from ev21w)
      and (select count(*) from room_memberships rm where rm.registration_id = er.id and rm.left_at is null) > 1),
  0::bigint,
  'test 43: retrying the allocation operation does not duplicate any membership');

-- ==================================================================== COORDINATOR REPLACEMENT

select pg_temp.as_staff(gen_random_uuid(), 'EVENT_ADMIN');

insert into public.events (
  slug, name, status, starts_at, timezone, timezone_label, capacity
) values ('test-night21-repl', 'Replacement Event', 'REGISTRATION', now() + interval '5 days', 'Africa/Lagos', 'WAT', 30);
create temporary table ev21r as select id from public.events where slug = 'test-night21-repl';

select pg_temp.register((select id from ev21r), 'oldcoord', '+2348055000001');
select pg_temp.register((select id from ev21r), 'newcoord', '+2348055000002');
select public.admin_create_room('test-night21-repl', 'REPL ROOM', 5,
  (select id from public.event_registrations where alias = 'oldcoord'));
create temporary table replroom as select id from rooms where event_id = (select id from ev21r) and label = 'REPL ROOM';

select public.admin_replace_room_coordinator('test-night21-repl', (select id from replroom),
  (select id from event_registrations where alias = 'newcoord'));

select is(
  (select count(*) from room_coordinators where room_id = (select id from replroom) and replaced_at is null),
  1::bigint,
  'test 43: exactly one active coordinator remains after replacement');
select is(
  (select registration_id from room_coordinators where room_id = (select id from replroom) and replaced_at is null),
  (select id from event_registrations where alias = 'newcoord'),
  'test 43: the new coordinator is the active one');
select isnt(
  (select registration_id from room_coordinators where room_id = (select id from replroom) and replaced_at is null),
  (select id from event_registrations where alias = 'oldcoord'),
  'test 43: the old coordinator no longer receives direct assignment (no longer active)');
select ok(
  exists (select 1 from room_coordinators where room_id = (select id from replroom) and registration_id = (select id from event_registrations where alias = 'oldcoord') and replaced_at is not null),
  'test 43: assignment history is preserved (old row still exists, marked replaced) — audit stays coherent');

-- Old coordinator, now free, can coordinate a different room.
select public.admin_create_room('test-night21-repl', 'REPL ROOM 2', 5,
  (select id from public.event_registrations where alias = 'oldcoord'));
select is(
  (select count(*) from room_coordinators where event_id = (select id from ev21r) and registration_id = (select id from event_registrations where alias = 'oldcoord') and replaced_at is null),
  1::bigint,
  'test 43: the freed former coordinator can be assigned to coordinate a different room');

-- ==================================================================== ROOM GAME PROGRESSION

select pg_temp.register((select id from ev21), 'progcoord1', '+2348056000001');
select pg_temp.register((select id from ev21), 'progcoord2', '+2348056000002');
select public.admin_create_room('test-night21', 'PROG ROOM 01', 5,
  (select id from public.event_registrations where alias = 'progcoord1'));
select public.admin_create_room('test-night21', 'PROG ROOM 02', 5,
  (select id from public.event_registrations where alias = 'progcoord2'));

create temporary table progroom1 as select id from rooms where event_id = (select id from ev21) and label = 'PROG ROOM 01';
create temporary table progroom2 as select id from rooms where event_id = (select id from ev21) and label = 'PROG ROOM 02';
create temporary table game1 as select id from event_games where event_id = (select id from ev21) and position = 1;
create temporary table game2 as select id from event_games where event_id = (select id from ev21) and position = 2;

-- Authorize as admin for these (already an EVENT_ADMIN session from setup).
select public.start_room_game((select id from progroom1), (select id from game1));
select is(
  (select status from room_event_games where room_id = (select id from progroom1) and event_game_id = (select id from game1)),
  'LIVE',
  'test 43: room 1 can start game 1');

select throws_like(
  $$ select public.start_room_game((select id from progroom1), (select id from game2)) $$,
  'room_game_already_live%',
  'test 43: same room cannot have two games live simultaneously');

select throws_like(
  $$ select public.start_room_game((select id from progroom2), (select id from game2)) $$,
  'game_order_violation%',
  'test 43: normal progression cannot skip the configured game order');

select public.start_round((select id from progroom1), (select id from game1));
select public.submit_round_result(
  (select id from rounds where room_id = (select id from progroom1) and event_game_id = (select id from game1) and round_index = 1),
  jsonb_build_object('scores', '[]'::jsonb),
  'idem-test43-progroom1-g1-0001'
);
select public.complete_room_game((select id from progroom1), (select id from game1));
select public.start_room_game((select id from progroom1), (select id from game2));
select is(
  (select status from room_event_games where room_id = (select id from progroom1) and event_game_id = (select id from game2)),
  'LIVE',
  'test 43: room 1 may complete game 1 and start game 2');

select public.start_room_game((select id from progroom2), (select id from game1));
select is(
  (select status from room_event_games where room_id = (select id from progroom2) and event_game_id = (select id from game1)),
  'LIVE',
  'test 43: room 2 independently remains on game 1 while room 1 is already on game 2');

select ok(
  (select started_at from room_event_games where room_id = (select id from progroom1) and event_game_id = (select id from game1)) is not null
  and (select ended_at from room_event_games where room_id = (select id from progroom1) and event_game_id = (select id from game1)) is not null,
  'test 43: started/ended timestamps are populated correctly for a completed room-game');

-- Cross-event room/game combination rejected: game1/game2 belong to ev21,
-- not ev21_other, and its rooms cannot reference them.
select pg_temp.register((select id from ev21_other), 'othercoord', '+2348056000003');
select public.admin_create_room('test-night21-other', 'OTHER ROOM', 5,
  (select id from public.event_registrations where alias = 'othercoord'));
select throws_ok(
  $$ select public.start_room_game(
       (select id from rooms where event_id = (select id from ev21_other) and label = 'OTHER ROOM'),
       (select id from game1)
     ) $$,
  'P0002', null,
  'test 43: a room cannot start a game belonging to a different event');

-- ==================================================================== DURATION

select lives_ok(
  $$ select public.admin_add_event_game('test-night21-other',
       (select id from games where slug = 'test-game21'), 1, 45) $$,
  'test 43: positive duration accepted');

select throws_like(
  $$ select public.admin_add_event_game('test-night21-other',
       (select id from games where slug = 'test-game21b'), 2, 0) $$,
  'invalid_duration%',
  'test 43: zero duration rejected');

select throws_like(
  $$ select public.admin_add_event_game('test-night21-other',
       (select id from games where slug = 'test-game21b'), 2, -5) $$,
  'invalid_duration%',
  'test 43: negative duration rejected');

select is(
  (select duration_minutes from event_games where event_id = (select id from ev21_other) and position = 1),
  45,
  'test 43: event-game duration is exposed through the read model (event_games.duration_minutes)');

-- ==================================================================== AUTHORIZATION / PRIVACY

select pg_temp.as_player(gen_random_uuid());
select throws_ok(
  $$ select public.admin_create_room('test-night21', 'HACKED ROOM', 5, null) $$,
  '42501', null,
  'test 43: an ordinary player cannot perform Admin room creation');

select throws_ok(
  $$ select public.admin_replace_room_coordinator('test-night21', (select id from progroom1), null) $$,
  '42501', null,
  'test 43: an ordinary player cannot replace a coordinator');

-- progcoord2 (an active coordinator of PROG ROOM 02) must not be able to
-- mutate PROG ROOM 01.
select pg_temp.as_player(gen_random_uuid());
update public.event_registrations set auth_user_id = (select current_setting('request.jwt.claim.sub')::uuid)
 where alias = 'progcoord2';
select throws_like(
  $$ select public.complete_room_game((select id from progroom1), (select id from game1)) $$,
  'not_authorized%',
  'test 43: a coordinator cannot mutate a different room''s game state');

-- Candidate list payload must never carry phone/real name.
select pg_temp.as_staff(gen_random_uuid(), 'EVENT_ADMIN');
select ok(
  not (public.admin_list_coordinator_candidates('test-night21')->0 ? 'phone'),
  'test 43: coordinator candidate payload never carries a phone field');
select ok(
  not (public.admin_list_coordinator_candidates('test-night21')->0 ? 'realName'),
  'test 43: coordinator candidate payload never carries a real name field');

select * from finish();
rollback;
