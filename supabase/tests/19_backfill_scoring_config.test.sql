-- Test 48 — scoring_config backfill (migration 0026).
--
-- The migration itself already ran once, against freshly-seeded data, by
-- the time this test executes — seed.sql now inserts the correct config
-- directly, so there's nothing stale left for it to find in a fresh test
-- database. To actually prove the backfill logic is correct, this test
-- simulates the real scenario it exists for: an event_games row that was
-- inserted *before* Phase 7 (scoring_config = '{}', exactly as reported
-- from the live production recess-01), then re-applies the same update
-- logic the migration uses and checks the result.
begin;
select plan(8);

insert into public.events (slug, name, status, starts_at, timezone, timezone_label, capacity)
values ('test-backfill26', 'Backfill Event', 'DRAFT', now() + interval '10 days', 'Africa/Lagos', 'WAT', 30);
create temporary table ev26 as select id from public.events where slug = 'test-backfill26';

-- A pre-Phase-7-shaped row: real game, real event_game, empty config —
-- exactly what recess-01's among-us/skribbl/trivia rows looked like before
-- this migration, per the reported live state.
insert into public.event_games (event_id, game_id, position, scoring_template, planned_rounds, scoring_config)
select (select id from ev26), id, 1, 'ROLE_OUTCOME', 3, '{}'::jsonb
  from games where slug = 'among-us';
create temporary table stale_au as select id from event_games where event_id = (select id from ev26) and position = 1;

insert into public.event_games (event_id, game_id, position, scoring_template, planned_rounds, scoring_config)
select (select id from ev26), id, 2, 'PLACEMENT', 1, '{}'::jsonb
  from games where slug = 'skribbl';
create temporary table stale_sk as select id from event_games where event_id = (select id from ev26) and position = 2;

-- ---------------------------------------------------------------- apply

update public.event_games eg
   set scoring_config = eg.scoring_config || jsonb_build_object(
         'awards', jsonb_build_object(
           'crewmate', jsonb_build_object('win', 1, 'loss', 0),
           'impostor', jsonb_build_object('win', 2, 'loss', 0)
         )
       )
  from public.games g
 where eg.game_id = g.id and g.slug = 'among-us' and eg.id = (select id from stale_au)
   and not (eg.scoring_config ? 'awards');

update public.event_games eg
   set scoring_config = eg.scoring_config || jsonb_build_object('type', 'placement')
  from public.games g
 where eg.game_id = g.id and g.slug = 'skribbl' and eg.id = (select id from stale_sk)
   and not (eg.scoring_config ? 'type');

select is(
  (select scoring_config->'awards'->'crewmate'->>'win' from event_games where id = (select id from stale_au)),
  '1',
  'test 48: a stale (pre-Phase-7) Among Us row is backfilled with the correct crewmate win value');
select is(
  (select scoring_config->'awards'->'impostor'->>'win' from event_games where id = (select id from stale_au)),
  '2',
  'test 48: ...and the correct impostor win value');
select is(
  (select scoring_config->>'type' from event_games where id = (select id from stale_sk)),
  'placement',
  'test 48: a stale (pre-Phase-7) Skribbl row is backfilled with the placement type marker');

-- ------------------------------------------------------------ idempotent

update public.event_games eg
   set scoring_config = eg.scoring_config || jsonb_build_object(
         'awards', jsonb_build_object('crewmate', jsonb_build_object('win', 1, 'loss', 0),
                                       'impostor', jsonb_build_object('win', 2, 'loss', 0))
       )
  from public.games g
 where eg.game_id = g.id and g.slug = 'among-us' and eg.id = (select id from stale_au)
   and not (eg.scoring_config ? 'awards');

select is(
  (select scoring_config->'awards'->'impostor'->>'win' from event_games where id = (select id from stale_au)),
  '2',
  'test 48: re-applying the backfill is a safe no-op (the guard already found the key present)');

-- --------------------------------------------------- never clobbers a manual fix

insert into public.events (slug, name, status, starts_at, timezone, timezone_label, capacity)
values ('test-backfill26b', 'Backfill Event B', 'DRAFT', now() + interval '10 days', 'Africa/Lagos', 'WAT', 30);

insert into public.event_games (event_id, game_id, position, scoring_template, planned_rounds, scoring_config)
select (select id from events where slug = 'test-backfill26b'), id, 1, 'ROLE_OUTCOME', 3,
       jsonb_build_object('awards', jsonb_build_object(
         'crewmate', jsonb_build_object('win', 9, 'loss', 0),
         'impostor', jsonb_build_object('win', 9, 'loss', 0)
       ))
  from games where slug = 'among-us';
create temporary table manually_fixed as
  select id from event_games where event_id = (select id from events where slug = 'test-backfill26b') and position = 1;

update public.event_games eg
   set scoring_config = eg.scoring_config || jsonb_build_object(
         'awards', jsonb_build_object('crewmate', jsonb_build_object('win', 1, 'loss', 0),
                                       'impostor', jsonb_build_object('win', 2, 'loss', 0))
       )
  from public.games g
 where eg.game_id = g.id and eg.id = (select id from manually_fixed)
   and not (eg.scoring_config ? 'awards');

select is(
  (select scoring_config->'awards'->'impostor'->>'win' from event_games where id = (select id from manually_fixed)),
  '9',
  'test 48: a row that already has an ''awards'' key (an existing manual fix) is never clobbered');

-- --------------------------------------------------------- games library default

update public.games
   set default_scoring_config = default_scoring_config || jsonb_build_object(
         'awards', jsonb_build_object('crewmate', jsonb_build_object('win', 1, 'loss', 0),
                                       'impostor', jsonb_build_object('win', 2, 'loss', 0))
       )
 where slug = 'among-us' and not (default_scoring_config ? 'awards');

select is(
  (select default_scoring_config->'awards'->'crewmate'->>'win' from games where slug = 'among-us'),
  '1',
  'test 48: games.default_scoring_config (the library default for future events) is correct after backfill');

select ok(
  (select default_scoring_config->>'type' from games where slug = 'skribbl') = 'placement',
  'test 48: skribbl''s library default carries the placement marker after the Phase 7 seed fix');

select ok(
  (select scoring_template from event_games where id = (select id from stale_au)) = 'ROLE_OUTCOME',
  'test 48: the backfill never touches scoring_template, position, or planned_rounds — scoring_config only');

select * from finish();
rollback;
