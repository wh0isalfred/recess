-- Test 41 — migration 0019: the Event Builder.
begin;
select plan(25);

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

insert into public.games (slug, name, platform, scoring_template, default_round_count, status)
values ('test-builder-game', 'Test Builder Game', 'BROWSER', 'PLACEMENT', 2, 'ACTIVE');

-- ----------------------------------------------------------------- authorization

select pg_temp.as_player(gen_random_uuid());
select throws_like(
  $$ select public.admin_create_event('test-builder-01', 'Test Builder Event', now() + interval '10 days',
       'Africa/Lagos', 'WAT', now() + interval '1 day', now() + interval '9 days', null, null, 30, null) $$,
  'not_authorized:%', 'test 41: a plain player cannot create an event');

select pg_temp.as_staff(gen_random_uuid(), 'EVENT_ADMIN');

-- --------------------------------------------------------------------- validation

select throws_like(
  $$ select public.admin_create_event('', 'No Slug', now() + interval '10 days',
       'Africa/Lagos', 'WAT', null, null, null, null, 30, null) $$,
  'invalid_slug:%', 'test 41: an empty slug is refused');
select throws_like(
  $$ select public.admin_create_event('test-builder-02', '', now() + interval '10 days',
       'Africa/Lagos', 'WAT', null, null, null, null, 30, null) $$,
  'invalid_name:%', 'test 41: an empty name is refused');
select throws_like(
  $$ select public.admin_create_event('test-builder-03', 'Bad Capacity', now() + interval '10 days',
       'Africa/Lagos', 'WAT', null, null, null, null, 0, null) $$,
  'invalid_capacity:%', 'test 41: a zero capacity is refused');
select throws_like(
  $$ select public.admin_create_event('test-builder-04', 'Bad WA', now() + interval '10 days',
       'Africa/Lagos', 'WAT', null, null, null, null, 30, 'https://evil.example.com') $$,
  'invalid_whatsapp_url:%', 'test 41: a non-WhatsApp url is refused');

-- ------------------------------------------------------------------------- create

select lives_ok(
  $$ select public.admin_create_event('test-builder-01', 'Test Builder Event', now() + interval '10 days',
       'Africa/Lagos', 'WAT', now() + interval '1 day', now() + interval '9 days', now() + interval '9 days 12 hours', now() + interval '10 days', 30, null) $$,
  'test 41: a valid event is created');

select is(
  (select status from events where slug = 'test-builder-01'), 'DRAFT'::event_status,
  'test 41: a newly created event lands at DRAFT, never LIVE/CHECK_IN');

select throws_like(
  $$ select public.admin_create_event('test-builder-01', 'Duplicate Slug', now() + interval '10 days',
       'Africa/Lagos', 'WAT', null, null, null, null, 30, null) $$,
  'slug_taken:%', 'test 41: creating a second event with the same slug is refused');

-- --------------------------------------------------------------------- list/get

select ok(
  (select public.admin_list_events() @> jsonb_build_array(jsonb_build_object('slug', 'test-builder-01'))),
  'test 41: admin_list_events includes the new event');

select is(
  (select public.admin_get_event('test-builder-01')->>'status'), 'DRAFT',
  'test 41: admin_get_event returns the real event detail');
select is(
  (select jsonb_array_length(public.admin_get_event('test-builder-01')->'games')), 0,
  'test 41: a freshly created event has no games yet');

-- ------------------------------------------------------------------- game library

select ok(
  (select public.admin_list_games() @> jsonb_build_array(jsonb_build_object('slug', 'test-builder-game'))
     or exists (select 1 from jsonb_array_elements(public.admin_list_games()) g where g->>'slug' = 'test-builder-game')),
  'test 41: admin_list_games includes an active game');

-- ------------------------------------------------------------------------ add game

select lives_ok(
  $$ select public.admin_add_event_game('test-builder-01',
       (select id from games where slug = 'test-builder-game'), 1) $$,
  'test 41: adding a game to the event succeeds');

select is(
  (select eg.scoring_template from event_games eg join games g on g.id=eg.game_id
    where g.slug='test-builder-game' and eg.event_id=(select id from events where slug='test-builder-01')),
  'PLACEMENT'::scoring_template, 'test 41: the event_game inherits the game''s own scoring template');
select is(
  (select eg.planned_rounds from event_games eg join games g on g.id=eg.game_id
    where g.slug='test-builder-game' and eg.event_id=(select id from events where slug='test-builder-01')),
  2, 'test 41: the event_game inherits the game''s own default round count');

select throws_like(
  $$ select public.admin_add_event_game('test-builder-01',
       (select id from games where slug = 'test-builder-game'), 2) $$,
  'game_already_added:%', 'test 41: the same game cannot be added twice to one event');

-- ----------------------------------------------------------- DRAFT -> REGISTRATION

-- Still no room, and no registration window issue — this event already has
-- both a window and (as of the insert above) a game, so opening
-- registration through the real transition_event() must now succeed.
select lives_ok(
  $$ select public.transition_event((select id from events where slug='test-builder-01'), 'REGISTRATION') $$,
  'test 41: DRAFT -> REGISTRATION succeeds once the builder has set a window and a game');

-- a second event, missing its registration window, must be refused by the
-- SAME existing guard — the builder adds no new lifecycle rule
select lives_ok(
  $$ select public.admin_create_event('test-builder-05', 'No Window', now() + interval '10 days',
       'Africa/Lagos', 'WAT', null, null, null, null, 30, null) $$,
  'test 41: a second event without a registration window is created (still DRAFT, that''s legal)');
select lives_ok(
  $$ select public.admin_add_event_game('test-builder-05',
       (select id from games where slug = 'test-builder-game'), 1) $$,
  'test 41: adding a game to the second event succeeds');
select throws_like(
  $$ select public.transition_event((select id from events where slug='test-builder-05'), 'REGISTRATION') $$,
  '%registration window is not set%',
  'test 41: transition_event still refuses to open registration without a window — unchanged, pre-existing rule');

-- ---------------------------------------------------- admin_open_registration wrapper

select pg_temp.as_player(gen_random_uuid());
select throws_like(
  $$ select public.admin_open_registration('test-builder-01') $$,
  'not_authorized:%', 'test 41: a plain player cannot open registration through the wrapper');

select pg_temp.as_staff(gen_random_uuid(), 'EVENT_ADMIN');
select lives_ok(
  $$ select public.admin_create_event('test-builder-06', 'Wrapper Test', now() + interval '10 days',
       'Africa/Lagos', 'WAT', now() + interval '1 day', now() + interval '9 days', null, null, 30, null) $$,
  'test 41: fixture event for the wrapper test is created');
select lives_ok(
  $$ select public.admin_add_event_game('test-builder-06',
       (select id from games where slug='test-builder-game'), 1) $$,
  'test 41: fixture event has a game');
select lives_ok(
  $$ select public.admin_open_registration('test-builder-06') $$,
  'test 41: an EVENT_ADMIN opens registration through the real wrapper');
select is(
  (select status from events where slug='test-builder-06'), 'REGISTRATION'::event_status,
  'test 41: the event actually transitioned via admin_open_registration');

select * from finish();
rollback;
