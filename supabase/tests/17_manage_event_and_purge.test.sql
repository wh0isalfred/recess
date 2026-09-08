-- Test 46 — safe permanent event deletion (migration 0024):
-- admin_purge_pre_event() and admin_list_event_games().
begin;
select plan(23);

create or replace function pg_temp.as_staff(p_uid uuid, p_role public.staff_role) returns void
language sql as $$
  insert into auth.users (id) values (p_uid);
  insert into public.staff_profiles (user_id, name, role) values (p_uid, 'Test Staff', p_role);
  select set_config('request.jwt.claim.sub', p_uid::text, true);
$$;

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

-- ==================================================== DRAFT, no registrations

select pg_temp.as_staff(gen_random_uuid(), 'SUPER_ADMIN');

insert into public.events (slug, name, status, starts_at, timezone, timezone_label, capacity)
values ('test-purge24-draft', 'Purge Draft Event', 'DRAFT', now() + interval '10 days', 'Africa/Lagos', 'WAT', 30);

select lives_ok(
  $$ select public.admin_purge_pre_event('test-purge24-draft') $$,
  'test 46: a DRAFT event with no registrations can be purged');
select ok(
  not exists (select 1 from events where slug = 'test-purge24-draft'),
  'test 46: the DRAFT event row is actually gone');

-- ==================================================== REGISTRATION, with registrations

insert into public.events (slug, name, status, starts_at, timezone, timezone_label, capacity)
values ('test-purge24-reg', 'Purge Registration Event', 'REGISTRATION', now() + interval '10 days', 'Africa/Lagos', 'WAT', 30);
create temporary table ev24reg as select id from public.events where slug = 'test-purge24-reg';

select pg_temp.register((select id from ev24reg), 'purgereg1', '+2348060000001');
select pg_temp.register((select id from ev24reg), 'purgereg2', '+2348060000002');
select pg_temp.register((select id from ev24reg), 'purgereg3', '+2348060000003');

create temporary table purge_player_ids as
  select player_id from event_registrations where event_id = (select id from ev24reg);

select is(
  (select public.admin_purge_pre_event('test-purge24-reg')->>'registrationsRemoved')::int,
  3,
  'test 46: registrationsRemoved correctly reports 3 for a REGISTRATION event with 3 registrations');

select is(
  (select count(*) from event_registrations where event_id = (select id from ev24reg)),
  0::bigint,
  'test 46: registrations were actually removed with the deleted event');

select is(
  (select count(*) from players where id in (select player_id from purge_player_ids)),
  3::bigint,
  'test 46: the underlying player rows remain — deleting a registration never deletes the global player record');

select ok(
  exists (select 1 from audit_logs where action = 'event.purged' and before->>'slug' = 'test-purge24-reg'),
  'test 46: audit history survives — the purge itself is recorded');
select is(
  (select event_id from audit_logs where action = 'event.purged' and before->>'slug' = 'test-purge24-reg'),
  null,
  'test 46: the surviving audit row''s event_id is correctly nulled (the event it named no longer exists)');
select is(
  (select (before->>'registrationsRemoved')::int from audit_logs where action = 'event.purged' and before->>'slug' = 'test-purge24-reg'),
  3,
  'test 46: the audit record correctly describes the number of registrations removed');

-- ==================================================== REGISTRATION_CLOSED accepted

insert into public.events (slug, name, status, starts_at, timezone, timezone_label, capacity)
values ('test-purge24-closed', 'Purge Closed Event', 'REGISTRATION_CLOSED', now() + interval '2 hours', 'Africa/Lagos', 'WAT', 30);

select lives_ok(
  $$ select public.admin_purge_pre_event('test-purge24-closed') $$,
  'test 46: a REGISTRATION_CLOSED event (also pre-check-in) can be purged');

-- ==================================================== rejected lifecycle states

insert into public.events (slug, name, status, starts_at, timezone, timezone_label, capacity)
values ('test-purge24-live', 'Purge Live Event', 'LIVE', now() - interval '1 hour', 'Africa/Lagos', 'WAT', 30);
select throws_like(
  $$ select public.admin_purge_pre_event('test-purge24-live') $$,
  'unsafe_lifecycle_state%',
  'test 46: a LIVE event is rejected');
select ok(
  exists (select 1 from events where slug = 'test-purge24-live'),
  'test 46: the rejected LIVE event still exists');

insert into public.events (slug, name, status, starts_at, timezone, timezone_label, capacity)
values ('test-purge24-complete', 'Purge Complete Event', 'COMPLETE', now() - interval '1 day', 'Africa/Lagos', 'WAT', 30);
select throws_like(
  $$ select public.admin_purge_pre_event('test-purge24-complete') $$,
  'unsafe_lifecycle_state%',
  'test 46: a COMPLETE event is rejected');

-- ==================================================== checked-in guard

insert into public.events (
  slug, name, status, starts_at, timezone, timezone_label,
  checkin_opens_at, checkin_closes_at, capacity
) values (
  'test-purge24-checkedin', 'Purge Checked-in Event', 'CHECK_IN',
  now() + interval '2 hours', 'Africa/Lagos', 'WAT',
  now() - interval '30 minutes', now() + interval '2 hours', 30
);
-- CHECK_IN itself is not in the allowed set, so first confirm it's rejected
-- purely on lifecycle grounds too, then separately prove the check-in guard
-- would independently catch a pre-event-state event with a checked-in row.
select throws_like(
  $$ select public.admin_purge_pre_event('test-purge24-checkedin') $$,
  'unsafe_lifecycle_state%',
  'test 46: a CHECK_IN-status event is rejected on lifecycle grounds alone');

insert into public.events (slug, name, status, starts_at, timezone, timezone_label, capacity)
values ('test-purge24-hascheckin', 'Purge Has-Checkin Event', 'REGISTRATION', now() + interval '10 days', 'Africa/Lagos', 'WAT', 30);
create temporary table ev24hc as select id from public.events where slug = 'test-purge24-hascheckin';
select pg_temp.register((select id from ev24hc), 'hascheckinreg', '+2348060000099');
update event_registrations set checked_in_at = now() where alias = 'hascheckinreg';
select throws_like(
  $$ select public.admin_purge_pre_event('test-purge24-hascheckin') $$,
  'players_checked_in%',
  'test 46: a pre-event-state event with a checked-in registration is rejected specifically on that ground');
select ok(
  exists (select 1 from events where slug = 'test-purge24-hascheckin'),
  'test 46: the rejected has-checkin event still exists, untouched');

-- ==================================================== authorization

insert into public.events (slug, name, status, starts_at, timezone, timezone_label, capacity)
values ('test-purge24-auth', 'Purge Auth Event', 'DRAFT', now() + interval '10 days', 'Africa/Lagos', 'WAT', 30);

select pg_temp.as_staff(gen_random_uuid(), 'EVENT_ADMIN');
select throws_ok(
  $$ select public.admin_purge_pre_event('test-purge24-auth') $$,
  '42501', null,
  'test 46: an EVENT_ADMIN cannot purge — SUPER_ADMIN only');
select ok(
  exists (select 1 from events where slug = 'test-purge24-auth'),
  'test 46: the event survives an EVENT_ADMIN''s rejected attempt');

select pg_temp.as_staff(gen_random_uuid(), 'SUPER_ADMIN');
select lives_ok(
  $$ select public.admin_purge_pre_event('test-purge24-auth') $$,
  'test 46: a SUPER_ADMIN can purge');

-- ==================================================== idempotency / not-found

select is(
  (select public.admin_purge_pre_event('test-purge24-auth')->>'alreadyDeleted'),
  'true',
  'test 46: purging an already-deleted (or never-existent) event slug is safe and idempotent, not a hard error');

-- ==================================================== admin_list_event_games

insert into public.events (slug, name, status, starts_at, timezone, timezone_label, capacity)
values ('test-purge24-games', 'Games List Event', 'DRAFT', now() + interval '10 days', 'Africa/Lagos', 'WAT', 30);
insert into public.games (slug, name, platform, scoring_template, status, artwork_url, default_round_count, default_duration_minutes)
values ('test-game24', 'Test Game 24', 'BROWSER', 'PLACEMENT', 'ACTIVE', '/games/test-game24.webp', 2, 25);
select public.admin_add_event_game('test-purge24-games', (select id from games where slug='test-game24'), 1);

select is(
  (select jsonb_array_length(public.admin_list_event_games('test-purge24-games'))),
  1,
  'test 46: admin_list_event_games returns the one configured game');
select is(
  (select public.admin_list_event_games('test-purge24-games')->0->>'durationMinutes')::int,
  25,
  'test 46: admin_list_event_games includes the correct duration');

-- ==================================================== real history still blocks

-- A pre-event-state event that somehow already has real scoring history
-- (the same scenario 05_history_and_rls.test.sql proves at the trigger
-- level directly) must still be refused by admin_purge_pre_event() even
-- though its status alone would otherwise permit deletion.
insert into public.events (slug, name, status, starts_at, timezone, timezone_label, capacity)
values ('test-purge24-history', 'Purge History Event', 'REGISTRATION', now() + interval '10 days', 'Africa/Lagos', 'WAT', 30);
create temporary table ev24h as select id from public.events where slug = 'test-purge24-history';

insert into public.rooms (event_id, label, position, capacity)
values ((select id from ev24h), 'HIST ROOM', 1, 5);
insert into public.games (slug, name, platform, scoring_template, status, artwork_url)
values ('test-game24h', 'Test Game 24h', 'BROWSER', 'ROLE_OUTCOME', 'ACTIVE', '/games/test-game24h.webp');
insert into public.event_games (event_id, game_id, position, scoring_template, planned_rounds)
values ((select id from ev24h), (select id from games where slug = 'test-game24h'), 1, 'ROLE_OUTCOME', 1);
insert into public.rounds (event_id, event_game_id, room_id, round_index)
select (select id from ev24h), eg.id, (select id from rooms where event_id = (select id from ev24h)), 1
  from event_games eg where eg.event_id = (select id from ev24h);
insert into public.results (event_id, round_id, template, payload, idempotency_key)
select (select id from ev24h), id, 'ROLE_OUTCOME', '{"winning_role":"impostor"}'::jsonb, 'idem-purge24-0001'
  from rounds where event_id = (select id from ev24h);

select throws_like(
  $$ select public.admin_purge_pre_event('test-purge24-history') $$,
  '%scoring history%',
  'test 46: a pre-event-state event with real scoring history is still refused, regardless of status');
select ok(
  exists (select 1 from events where slug = 'test-purge24-history'),
  'test 46: the event with real history survives the rejected purge attempt');

select * from finish();
rollback;
