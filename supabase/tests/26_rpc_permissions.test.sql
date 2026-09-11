-- Test 55 — RPC execution permission hardening (migration 0033).
--
-- has_function_privilege(role, signature, 'execute') checks the actual
-- Postgres ACL for that role, correctly accounting for any inherited
-- PUBLIC grant — this is the real boundary, not the JWT claim game the
-- rest of this suite plays. Every signature below is the exact type
-- list, not just a bare function name, per the brief's own instruction.
begin;
select plan(58);

-- ==================================================================== INTERNAL

select ok(
  not has_function_privilege('anon', 'public.room_standings_compute(uuid, uuid)', 'execute'),
  'test 55: anon cannot execute room_standings_compute()');
select ok(
  not has_function_privilege('authenticated', 'public.room_standings_compute(uuid, uuid)', 'execute'),
  'test 55: authenticated cannot execute room_standings_compute()');

select ok(
  not has_function_privilege('anon', 'public.room_game_ready_to_settle(uuid, uuid)', 'execute'),
  'test 55: anon cannot execute room_game_ready_to_settle()');
select ok(
  not has_function_privilege('authenticated', 'public.room_game_ready_to_settle(uuid, uuid)', 'execute'),
  'test 55: authenticated cannot execute room_game_ready_to_settle()');

select ok(
  not has_function_privilege('anon', 'public.validate_round_payload(uuid, jsonb)', 'execute'),
  'test 55: anon cannot execute validate_round_payload()');
select ok(
  not has_function_privilege('authenticated', 'public.validate_round_payload(uuid, jsonb)', 'execute'),
  'test 55: authenticated cannot execute validate_round_payload()');

select ok(
  not has_function_privilege('anon', 'public.apply_round_correction(uuid, jsonb, uuid, text, jsonb)', 'execute'),
  'test 55: anon cannot execute apply_round_correction()');
select ok(
  not has_function_privilege('authenticated', 'public.apply_round_correction(uuid, jsonb, uuid, text, jsonb)', 'execute'),
  'test 55: authenticated cannot execute apply_round_correction()');

select ok(
  not has_function_privilege('anon', 'public.settle_room_game_now(uuid, uuid)', 'execute'),
  'test 55: anon cannot execute settle_room_game_now()');
select ok(
  not has_function_privilege('authenticated', 'public.settle_room_game_now(uuid, uuid)', 'execute'),
  'test 55: authenticated cannot execute settle_room_game_now()');

select ok(
  not has_function_privilege('anon', 'public.assert_coordinator_eligible(uuid, uuid)', 'execute'),
  'test 55: anon cannot execute assert_coordinator_eligible()');
select ok(
  not has_function_privilege('authenticated', 'public.assert_coordinator_eligible(uuid, uuid)', 'execute'),
  'test 55: authenticated cannot execute assert_coordinator_eligible()');

select ok(
  not has_function_privilege('anon', 'public.require_event_admin()', 'execute'),
  'test 55: anon cannot execute require_event_admin()');
select ok(
  not has_function_privilege('authenticated', 'public.require_event_admin()', 'execute'),
  'test 55: authenticated cannot execute require_event_admin()');

select ok(
  not has_function_privilege('anon', 'public.is_authorized_for_room(uuid)', 'execute'),
  'test 55: anon cannot execute is_authorized_for_room()');
select ok(
  not has_function_privilege('authenticated', 'public.is_authorized_for_room(uuid)', 'execute'),
  'test 55: authenticated cannot execute is_authorized_for_room()');

select ok(
  not has_function_privilege('anon', 'public.current_staff_role()', 'execute'),
  'test 55: anon cannot execute current_staff_role()');
select ok(
  not has_function_privilege('authenticated', 'public.current_staff_role()', 'execute'),
  'test 55: authenticated cannot execute current_staff_role()');

-- Trigger functions discovered by the audit — genuinely internal,
-- never a client-facing surface.
select ok(
  not has_function_privilege('anon', 'public.refuse_delete()', 'execute'),
  'test 55: anon cannot execute refuse_delete() (a trigger function, found with zero prior grant/revoke history)');
select ok(
  not has_function_privilege('authenticated', 'public.refuse_delete()', 'execute'),
  'test 55: authenticated cannot execute refuse_delete()');
select ok(
  not has_function_privilege('anon', 'public.events_status_guard()', 'execute'),
  'test 55: anon cannot execute events_status_guard()');
select ok(
  not has_function_privilege('authenticated', 'public.events_status_guard()', 'execute'),
  'test 55: authenticated cannot execute events_status_guard()');

-- ==================================================================== EVENT LIFECYCLE

select ok(
  not has_function_privilege('anon', 'public.transition_event(uuid, public.event_status, text)', 'execute'),
  'test 55: anon cannot execute transition_event()');
select ok(
  not has_function_privilege('authenticated', 'public.transition_event(uuid, public.event_status, text)', 'execute'),
  'test 55: authenticated cannot execute transition_event() — it remains internal-only');
select ok(
  has_function_privilege('authenticated', 'public.admin_open_check_in(text)', 'execute'),
  'test 55: the proper authenticated admin wrapper (admin_open_check_in) remains executable');
select ok(
  has_function_privilege('authenticated', 'public.admin_open_registration(text)', 'execute'),
  'test 55: the proper authenticated admin wrapper (admin_open_registration) remains executable');

-- Functional: an ordinary authenticated player calling that admin
-- wrapper still fails its own internal authorization, regardless of the
-- ACL permitting the call to reach the function body at all.
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

insert into public.events (slug, name, status, starts_at, timezone, timezone_label, registration_opens_at, registration_closes_at, capacity)
values ('test-perm55', 'Permission Test Event', 'REGISTRATION', now() + interval '2 days', 'Africa/Lagos', 'WAT', now() - interval '1 day', now() + interval '30 days', 30);

select pg_temp.as_player(gen_random_uuid());
select throws_like(
  $$ select public.admin_open_check_in('test-perm55') $$,
  'not_authorized%',
  'test 55: an ordinary authenticated player calling the admin wrapper still fails its own internal staff check');

-- ==================================================================== PLAYER

select ok(
  not has_function_privilege('anon', 'public.get_player_state()', 'execute'),
  'test 55: anon cannot execute get_player_state() — no pre-auth access is genuinely required');
select ok(
  has_function_privilege('authenticated', 'public.get_player_state()', 'execute'),
  'test 55: authenticated can execute get_player_state()');
select ok(
  has_function_privilege('authenticated', 'public.get_my_game_progress()', 'execute'),
  'test 55: authenticated can execute get_my_game_progress()');
select ok(
  has_function_privilege('authenticated', 'public.get_my_room_standings()', 'execute'),
  'test 55: authenticated can execute get_my_room_standings()');
select ok(
  not has_function_privilege('anon', 'public.get_my_game_progress()', 'execute'),
  'test 55: anon cannot execute get_my_game_progress()');
select ok(
  not has_function_privilege('anon', 'public.get_my_room_standings()', 'execute'),
  'test 55: anon cannot execute get_my_room_standings()');
select ok(
  has_function_privilege('authenticated', 'public.check_in_player()', 'execute'),
  'test 55: authenticated can execute check_in_player()');
select ok(
  has_function_privilege('authenticated', 'public.recover_player_access()', 'execute'),
  'test 55: authenticated can execute recover_player_access()');
select ok(
  has_function_privilege('authenticated', 'public.register_player(text, text, text, text, boolean)', 'execute'),
  'test 55: authenticated can execute register_player()');
select ok(
  not has_function_privilege('anon', 'public.register_player(text, text, text, text, boolean)', 'execute'),
  'test 55: anon cannot execute register_player() — an anonymous Auth session runs as authenticated, not as the anon database role');

-- ==================================================================== COORDINATOR

select ok(
  has_function_privilege('authenticated', 'public.coordinator_room_state(uuid)', 'execute'),
  'test 55: authenticated can execute coordinator_room_state()');
select ok(
  has_function_privilege('authenticated', 'public.coordinator_room_standings(uuid)', 'execute'),
  'test 55: authenticated can execute coordinator_room_standings()');
select ok(
  has_function_privilege('authenticated', 'public.start_room_game(uuid, uuid)', 'execute'),
  'test 55: authenticated can execute start_room_game()');
select ok(
  has_function_privilege('authenticated', 'public.start_round(uuid, uuid)', 'execute'),
  'test 55: authenticated can execute start_round()');
select ok(
  has_function_privilege('authenticated', 'public.submit_round_result(uuid, jsonb, text)', 'execute'),
  'test 55: authenticated can execute submit_round_result()');
select ok(
  has_function_privilege('authenticated', 'public.complete_room_game(uuid, uuid)', 'execute'),
  'test 55: authenticated can execute complete_room_game()');
select ok(
  has_function_privilege('authenticated', 'public.request_result_correction(uuid, jsonb, text)', 'execute'),
  'test 55: authenticated can execute request_result_correction()');
select ok(
  not has_function_privilege('anon', 'public.start_round(uuid, uuid)', 'execute'),
  'test 55: anon cannot execute start_round()');
select ok(
  not has_function_privilege('anon', 'public.complete_room_game(uuid, uuid)', 'execute'),
  'test 55: anon cannot execute complete_room_game()');

-- Functional: an ordinary (non-coordinator) authenticated player still
-- gets refused by the function's own authorization, ACL access
-- notwithstanding.
select pg_temp.as_staff(gen_random_uuid(), 'SUPER_ADMIN');
insert into public.events (slug, name, status, starts_at, timezone, timezone_label, capacity)
values ('test-perm55-room', 'Permission Test Room Event', 'LIVE', now() - interval '1 hour', 'Africa/Lagos', 'WAT', 30);
insert into public.players (phone_e164, real_name, canonical_alias) values ('+2348140000001', 'permcoord', 'permcoord');
create temporary table perm_player_no as
  with bumped as (
    update public.event_counters set next_player_no = next_player_no + 1
     where event_id = (select id from events where slug='test-perm55-room') returning next_player_no
  )
  select next_player_no - 1 as no from bumped;
insert into public.event_registrations (event_id, player_id, alias, player_number, status, auth_user_id)
select (select id from events where slug='test-perm55-room'), (select id from players where canonical_alias='permcoord'),
       'permcoord', (select no from perm_player_no), 'REGISTERED', gen_random_uuid();
select public.admin_create_room('test-perm55-room', 'PERM ROOM 01', 8,
  (select id from event_registrations where alias='permcoord'));
create temporary table perm_unrelated_room as select id from rooms where event_id=(select id from events where slug='test-perm55-room');

select pg_temp.as_player(gen_random_uuid());
select throws_ok(
  $$ select public.coordinator_room_standings((select id from perm_unrelated_room)) $$,
  '42501', null,
  'test 55: an ordinary authenticated player calling a coordinator RPC for a room they have no relation to still fails its own authorization');

-- ==================================================================== ADMIN

select ok(
  has_function_privilege('authenticated', 'public.admin_create_event(text, text, timestamptz, text, text, timestamptz, timestamptz, timestamptz, timestamptz, integer, text)', 'execute'),
  'test 55: authenticated can execute admin_create_event()');
select ok(
  has_function_privilege('authenticated', 'public.admin_approve_correction(uuid)', 'execute'),
  'test 55: authenticated can execute admin_approve_correction()');
select ok(
  has_function_privilege('authenticated', 'public.admin_manual_adjustment(text, uuid, integer, text)', 'execute'),
  'test 55: authenticated can execute admin_manual_adjustment()');
select ok(
  not has_function_privilege('anon', 'public.admin_create_event(text, text, timestamptz, text, text, timestamptz, timestamptz, timestamptz, timestamptz, integer, text)', 'execute'),
  'test 55: anon cannot execute admin_create_event()');
select ok(
  not has_function_privilege('anon', 'public.admin_approve_correction(uuid)', 'execute'),
  'test 55: anon cannot execute admin_approve_correction()');

-- Functional: a non-staff authenticated session still gets refused by
-- the RPC's own internal staff check.
select pg_temp.as_player(gen_random_uuid());
select throws_like(
  $$ select public.admin_manual_adjustment('test-perm55', gen_random_uuid(), 5, 'test') $$,
  'not_authorized%',
  'test 55: a non-staff authenticated session still receives not_authorized from an admin RPC''s own logic');

-- ==================================================================== PUBLIC / PRE-AUTH

-- This set should be very small — deliberately empty in this codebase.
-- Spot-check that a handful of representative functions across every
-- category are NOT anon-executable, i.e. nothing was accidentally left
-- (or restored) as pre-auth.
select ok(
  not has_function_privilege('anon', 'public.admin_list_events()', 'execute'),
  'test 55: anon cannot execute admin_list_events()');
select ok(
  not has_function_privilege('anon', 'public.void_round(uuid, text)', 'execute'),
  'test 55: anon cannot execute void_round()');
select ok(
  not has_function_privilege('anon', 'public.preview_round_result(uuid, jsonb)', 'execute'),
  'test 55: anon cannot execute preview_round_result()');

-- ==================================================================== REGRESSION: coordinator standings hotfix + player access still green

select ok(
  has_function_privilege('authenticated', 'public.room_standings(uuid)', 'execute'),
  'test 55: authenticated (staff, via its own require_event_admin() check) can still reach room_standings()');
select ok(
  not has_function_privilege('anon', 'public.room_standings(uuid)', 'execute'),
  'test 55: anon cannot execute room_standings()');

select * from finish();
rollback;
