-- Tests 2, 3, 4, 4b, 16 — schema existence, seed replay, event graph, timezone.
begin;
select plan(28);

-- ---- test 2: schema existence -------------------------------------------
select is(
  (select count(*)::int from pg_tables
    where schemaname = 'public' and tablename in (
      'players','staff_profiles','events','event_counters','event_registrations',
      'games','event_games','rooms','room_memberships','coordinator_assignments',
      'rounds','round_participants','results','point_transactions',
      'awards','award_recipients','audit_logs')),
  17, 'test 2: all 17 approved tables exist');

select is(
  (select count(*)::int from pg_type t
    join pg_namespace n on n.oid = t.typnamespace
   where n.nspname = 'public' and t.typtype = 'e'),
  11, 'test 2: all 11 enums exist');

select is(
  (select array_agg(e.enumlabel::text order by e.enumsortorder)
     from pg_type t join pg_enum e on e.enumtypid = t.oid
    where t.typname = 'event_status'),
  array['DRAFT','REGISTRATION','REGISTRATION_CLOSED','CHECK_IN','LIVE','PAUSED','COMPLETE','CANCELLED'],
  'test 2: event_status has exactly the approved values in order');

select is(
  (select array_agg(e.enumlabel::text order by e.enumsortorder)
     from pg_type t join pg_enum e on e.enumtypid = t.oid
    where t.typname = 'scoring_template'),
  array['PLACEMENT','ROLE_OUTCOME','TEAM_OUTCOME','INDIVIDUAL_OUTCOME','MANUAL'],
  'test 2: scoring_template has exactly the approved values');

select has_index('public','room_memberships','room_memberships_active_key',
  'test 2: partial unique index for one active membership exists');
select has_index('public','event_registrations','event_registrations_alias_key',
  'test 2: case-insensitive alias index exists');
select has_index('public','results','results_authoritative_key',
  'test 2: one-authoritative-result index exists');
select has_index('public','point_transactions','point_transactions_result_player_key',
  'test 2: a result cannot credit a player twice');

-- [r3] the constraint that was removed must stay removed
select is(
  (select count(*)::int from pg_constraint
    where conrelid = 'public.room_memberships'::regclass and contype = 'u'),
  0, 'test 2 [r3]: room_memberships carries no table-level unique constraint');

-- [r3] both ordering constraints are deferrable
select is((select condeferrable from pg_constraint where conname = 'rooms_position_key'),
  true, 'test 2 [r3]: rooms position uniqueness is deferrable');
select is((select condeferred from pg_constraint where conname = 'rooms_position_key'),
  true, 'test 2 [r3]: rooms position uniqueness is initially deferred');
select is((select condeferrable from pg_constraint where conname = 'event_games_position_key'),
  true, 'test 2: event_games position uniqueness is deferrable');

-- awards can never become points: structural, not conventional
select hasnt_column('public','point_transactions','award_id',
  'test 2: point_transactions has no award_id column');
select is(
  (select count(*)::int from pg_constraint
    where conrelid = 'public.point_transactions'::regclass
      and confrelid = 'public.awards'::regclass),
  0, 'test 2: no foreign key from the ledger to awards');

-- ---- test 3: seed replay -------------------------------------------------
select is((select count(*)::int from public.games), 3, 'test 3: exactly 3 games');
select is((select count(*)::int from public.events), 1, 'test 3: exactly 1 event');
select is((select count(*)::int from public.event_games), 3, 'test 3: exactly 3 event games');
select is((select count(*)::int from public.rooms), 2, 'test 3: exactly 2 rooms');
select is((select count(*)::int from public.event_counters), 1, 'test 3: counter created by trigger');
select is(
  (select count(*)::int from public.event_registrations)
  + (select count(*)::int from public.players)
  + (select count(*)::int from public.rounds)
  + (select count(*)::int from public.results)
  + (select count(*)::int from public.point_transactions),
  0, 'test 3: no players, registrations, rounds, results or transactions seeded');

-- ---- test 4: complete event graph ---------------------------------------
select is(
  (select array_agg(coalesce(eg.display_name, g.name) order by eg.position)
     from public.event_games eg
     join public.games g on g.id = eg.game_id
     join public.events e on e.id = eg.event_id
    where e.slug = 'recess-01'),
  array['Skribbl','Among Us','Trivia'],
  'test 4: games join in position order 1,2,3');

select is(
  (select eg.scoring_config from public.event_games eg
     join public.games g on g.id = eg.game_id where g.slug = 'among-us'),
  (select default_scoring_config from public.games where slug = 'among-us'),
  'test 4: Among Us config copied from library byte-for-byte');

-- ---- test 4b [r2]: no impostor default anywhere --------------------------
select ok(
  (select default_scoring_config #> '{composition,impostor}' ? 'default'
     from public.games where slug = 'among-us') is not true,
  'test 4b: library Among Us composition has no default impostor count');
select is(
  (select (default_scoring_config #>> '{composition,impostor,min}')::int || '-' ||
          (default_scoring_config #>> '{composition,impostor,max}')::int
     from public.games where slug = 'among-us'),
  '1-3', 'test 4b: composition describes the supported 1-3 range');
select is(
  (select count(*)::int from information_schema.columns
    where table_schema = 'public' and column_name ilike '%impostor%'),
  0, 'test 4b: no column anywhere mentions impostors');

-- ---- test 16: timezone fidelity ------------------------------------------
select is(
  (select (starts_at at time zone timezone)::text from public.events where slug='recess-01'),
  '2026-09-11 20:00:00', 'test 16: renders as 20:00 in the event timezone');
select is(
  (select to_char(starts_at at time zone timezone, 'Dy') from public.events where slug='recess-01'),
  'Fri', 'test 16: 11 September 2026 is a Friday');
select is(
  (select (starts_at at time zone 'UTC')::text from public.events where slug='recess-01'),
  '2026-09-11 19:00:00', 'test 16: stored as 19:00 UTC');

select * from finish();
rollback;
