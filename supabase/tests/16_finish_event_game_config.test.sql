-- Test 45 — finish event-game configuration (migration 0023):
-- admin_add_event_game's planned_rounds override, and admin_update_event_game.
begin;
select plan(18);

create or replace function pg_temp.as_staff(p_uid uuid, p_role public.staff_role) returns void
language sql as $$
  insert into auth.users (id) values (p_uid);
  insert into public.staff_profiles (user_id, name, role) values (p_uid, 'Test Staff', p_role);
  select set_config('request.jwt.claim.sub', p_uid::text, true);
$$;

select pg_temp.as_staff(gen_random_uuid(), 'EVENT_ADMIN');

-- ---------------------------------------------------------------------- fixture

insert into public.events (slug, name, status, starts_at, timezone, timezone_label, capacity)
values ('test-cfg23', 'Config Event', 'DRAFT', now() + interval '10 days', 'Africa/Lagos', 'WAT', 30);
create temporary table ev23 as select id from public.events where slug = 'test-cfg23';

insert into public.games (slug, name, platform, scoring_template, status, artwork_url, default_round_count, default_duration_minutes)
values ('test-game23a', 'Test Game 23a', 'BROWSER', 'PLACEMENT', 'ACTIVE', '/games/test-game23a.webp', 3, 45);
insert into public.games (slug, name, platform, scoring_template, status, artwork_url)
values ('test-game23b', 'Test Game 23b', 'BROWSER', 'PLACEMENT', 'ACTIVE', '/games/test-game23b.webp');

-- ==================================================== ADD-TIME: planned_rounds

-- No override -> falls back to the library default (3), exactly like
-- duration already does.
select public.admin_add_event_game('test-cfg23', (select id from games where slug = 'test-game23a'), 1);
select is(
  (select planned_rounds from event_games where event_id = (select id from ev23) and position = 1),
  3,
  'test 45: no planned_rounds override falls back to the library default_round_count');
select is(
  (select duration_minutes from event_games where event_id = (select id from ev23) and position = 1),
  45,
  'test 45: no duration override falls back to the library default_duration_minutes (unchanged 0021 behavior)');

-- Explicit override -> wins over the library default.
select public.admin_add_event_game('test-cfg23', (select id from games where slug = 'test-game23b'), 2, 20, 5);
select is(
  (select planned_rounds from event_games where event_id = (select id from ev23) and position = 2),
  5,
  'test 45: an explicit planned_rounds override wins over the library default');
select is(
  (select duration_minutes from event_games where event_id = (select id from ev23) and position = 2),
  20,
  'test 45: an explicit duration override still works alongside a rounds override');

select throws_like(
  $$ select public.admin_add_event_game('test-cfg23',
       (select id from games where slug = 'test-game23a'), 3, 20, 0) $$,
  'invalid_rounds%',
  'test 45: zero planned_rounds is rejected at add-time');
select throws_like(
  $$ select public.admin_add_event_game('test-cfg23',
       (select id from games where slug = 'test-game23a'), 3, 20, -1) $$,
  'invalid_rounds%',
  'test 45: negative planned_rounds is rejected at add-time');

-- ==================================================== admin_update_event_game

create temporary table eg1 as select id from event_games where event_id = (select id from ev23) and position = 1;

select lives_ok(
  $$ select public.admin_update_event_game('test-cfg23', (select id from eg1), 60, null) $$,
  'test 45: updating duration alone succeeds');
select is(
  (select duration_minutes from event_games where id = (select id from eg1)), 60,
  'test 45: duration was actually updated');
select is(
  (select planned_rounds from event_games where id = (select id from eg1)), 3,
  'test 45: planned_rounds was left untouched when only duration was passed');

select lives_ok(
  $$ select public.admin_update_event_game('test-cfg23', (select id from eg1), null, 7) $$,
  'test 45: updating planned_rounds alone succeeds');
select is(
  (select planned_rounds from event_games where id = (select id from eg1)), 7,
  'test 45: planned_rounds was actually updated');
select is(
  (select duration_minutes from event_games where id = (select id from eg1)), 60,
  'test 45: duration was left untouched when only planned_rounds was passed (not reset to the library default)');

select lives_ok(
  $$ select public.admin_update_event_game('test-cfg23', (select id from eg1), 90, 2) $$,
  'test 45: updating both values in one call succeeds');
select is(
  (select (duration_minutes, planned_rounds) from event_games where id = (select id from eg1)),
  (90, 2),
  'test 45: both values were updated together correctly');

select throws_like(
  $$ select public.admin_update_event_game('test-cfg23', (select id from eg1), 0, null) $$,
  'invalid_duration%',
  'test 45: zero duration is rejected on update');
select throws_like(
  $$ select public.admin_update_event_game('test-cfg23', (select id from eg1), null, -3) $$,
  'invalid_rounds%',
  'test 45: negative planned_rounds is rejected on update');

select throws_like(
  $$ select public.admin_update_event_game('test-cfg23', gen_random_uuid(), 10, null) $$,
  'event_game_not_found%',
  'test 45: updating a non-existent event_game id is rejected');

-- ==================================================== AUTHORIZATION

select pg_temp.as_staff(gen_random_uuid(), 'COORDINATOR');
select throws_ok(
  $$ select public.admin_update_event_game('test-cfg23', (select id from eg1), 15, null) $$,
  '42501', null,
  'test 45: a COORDINATOR cannot update event-game configuration');

select * from finish();
rollback;
