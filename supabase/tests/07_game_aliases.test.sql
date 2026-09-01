-- Tests 18-32 — game-specific player aliases (Phase 1 follow-up amendment).
begin;
select plan(22);

create temporary table t as select id as event_id from public.events where slug='recess-01';

insert into public.players (phone_e164, real_name, canonical_alias) values
  ('+2348000000031','Alfred Enyinna','WH0ISALFRED'),
  ('+2348000000032','Davo Second','DAVO');

insert into public.event_registrations (event_id, player_id, alias, player_number)
select (select event_id from t), id, canonical_alias,
       row_number() over (order by phone_e164)
  from public.players;

create temporary table g as
select
  (select eg.id from public.event_games eg join public.games ga on ga.id=eg.game_id
    where ga.slug='among-us') as among_us,
  (select eg.id from public.event_games eg join public.games ga on ga.id=eg.game_id
    where ga.slug='skribbl') as skribbl;

create temporary table reg as
select
  (select id from public.event_registrations where alias='WH0ISALFRED') as alfred,
  (select id from public.event_registrations where alias='DAVO') as davo;

-- ---- test 18: a valid alias can be created -------------------------------
select lives_ok(
  $$ insert into public.game_aliases (event_id, registration_id, event_game_id, alias)
     select (select event_id from t), (select alfred from reg), (select among_us from g),
            'alfred2009' $$,
  'test 18: a valid game alias is accepted');

select is(
  (select alias from public.game_aliases where registration_id = (select alfred from reg)),
  'alfred2009', 'test 18: the alias round-trips');

-- ---- test 19/20: ownership is enforced -----------------------------------
select throws_ok(
  $$ insert into public.game_aliases (event_id, registration_id, event_game_id, alias)
     select (select event_id from t), gen_random_uuid(), (select among_us from g), 'ghost' $$,
  '23503', null, 'test 19: an alias for an unknown registration is rejected');

select throws_ok(
  $$ insert into public.game_aliases (event_id, registration_id, event_game_id, alias)
     select (select event_id from t), (select davo from reg), gen_random_uuid(), 'ghostgame' $$,
  '23503', null, 'test 20: an alias for a game that is not in this event is rejected');

-- ---- test 21: cross-event is rejected ------------------------------------
insert into public.events (slug, name, starts_at, capacity)
values ('alias-other','Other', now() + interval '40 days', 10);
insert into public.event_games (event_id, game_id, position, scoring_template, scoring_config)
select e.id, ga.id, 1, ga.scoring_template, ga.default_scoring_config
  from public.events e cross join public.games ga
 where e.slug='alias-other' and ga.slug='among-us';

select throws_ok(
  $$ insert into public.game_aliases (event_id, registration_id, event_game_id, alias)
     select (select id from public.events where slug='alias-other'),
            (select davo from reg),
            (select eg.id from public.event_games eg
               join public.events e on e.id = eg.event_id where e.slug='alias-other'),
            'crossevent' $$,
  '23503', null, 'test 21: event A registration cannot alias into event B game');

-- ---- test 22: one alias per registration per event game ------------------
select throws_ok(
  $$ insert into public.game_aliases (event_id, registration_id, event_game_id, alias)
     select (select event_id from t), (select alfred from reg), (select among_us from g),
            'secondname' $$,
  '23505', null, 'test 22: a second alias for the same player and game is rejected');

-- ---- test 23/24: alias uniqueness within the event game ------------------
select throws_ok(
  $$ insert into public.game_aliases (event_id, registration_id, event_game_id, alias)
     select (select event_id from t), (select davo from reg), (select among_us from g),
            'alfred2009' $$,
  '23505', null, 'test 23: two players cannot claim the same external name');

select throws_ok(
  $$ insert into public.game_aliases (event_id, registration_id, event_game_id, alias)
     select (select event_id from t), (select davo from reg), (select among_us from g),
            'ALFRED2009' $$,
  '23505', null, 'test 24: uniqueness is case-insensitive');

-- ---- test 25: case is preserved exactly ----------------------------------
insert into public.game_aliases (event_id, registration_id, event_game_id, alias)
select (select event_id from t), (select davo from reg), (select skribbl from g), 'DaVo_ThE_GoAt';
select is(
  (select alias from public.game_aliases
    where registration_id = (select davo from reg) and event_game_id = (select skribbl from g)),
  'DaVo_ThE_GoAt', 'test 25: the alias is stored exactly as typed');

-- ---- test 26: the same name in a different game slot is fine -------------
select lives_ok(
  $$ insert into public.game_aliases (event_id, registration_id, event_game_id, alias)
     select (select event_id from t), (select alfred from reg), (select skribbl from g),
            'alfred2009' $$,
  'test 26: the same external name in a different game slot is allowed');

-- ---- test 27/28: charset and shape ---------------------------------------
create temporary table trivia as
select eg.id from public.event_games eg join public.games ga on ga.id=eg.game_id
 where ga.slug='trivia';

select lives_ok(
  $$ insert into public.game_aliases (event_id, registration_id, event_game_id, alias)
     select (select event_id from t), (select alfred from reg), (select id from trivia),
            'Big Al' $$,
  'test 27: spaces are permitted in an external game name');

select throws_ok(
  $$ insert into public.game_aliases (event_id, registration_id, event_game_id, alias)
     select (select event_id from t), (select davo from reg), (select id from trivia),
            E'tab\there' $$,
  '23514', null, 'test 27: control characters are rejected');

select throws_ok(
  $$ insert into public.game_aliases (event_id, registration_id, event_game_id, alias)
     select (select event_id from t), (select davo from reg), (select id from trivia), '' $$,
  '23514', null, 'test 28: an empty alias is rejected');

select throws_ok(
  $$ insert into public.game_aliases (event_id, registration_id, event_game_id, alias)
     select (select event_id from t), (select davo from reg), (select id from trivia),
            '  padded  ' $$,
  '23514', null, 'test 28: an untrimmed alias is rejected');

-- ---- test 29: update is permitted and audited ----------------------------
select lives_ok(
  $$ update public.game_aliases set alias = 'alfred_2026'
      where registration_id = (select alfred from reg)
        and event_game_id = (select among_us from g) $$,
  'test 29: an alias can be changed');

select is(
  (select count(*)::int from public.audit_logs
    where action = 'game_alias.changed'
      and before->>'alias' = 'alfred2009' and after->>'alias' = 'alfred_2026'),
  1, 'test 29: the change is recorded in the audit log with before and after');

-- ---- test 30: delete is permitted and audited ----------------------------
select lives_ok(
  $$ delete from public.game_aliases
      where registration_id = (select davo from reg)
        and event_game_id = (select skribbl from g) $$,
  'test 30: an alias can be deleted');

select is(
  (select count(*)::int from public.audit_logs where action = 'game_alias.deleted'),
  1, 'test 30: the deletion is recorded in the audit log');

-- ---- test 31: cascade from a DRAFT event ---------------------------------
select lives_ok(
  $$ delete from public.events where slug = 'alias-other' $$,
  'test 31: a DRAFT event carrying game slots can still be deleted');

select is(
  (select count(*)::int from public.game_aliases ga
    where not exists (select 1 from public.events e where e.id = ga.event_id)),
  0, 'test 31: no orphan aliases remain');

-- ---- test 32: RLS still denies clients -----------------------------------
set local role anon;
select is((select count(*)::int from public.game_aliases), 0,
  'test 32: anon sees zero aliases');
select throws_ok(
  $$ insert into public.game_aliases (event_id, registration_id, event_game_id, alias)
     values (gen_random_uuid(), gen_random_uuid(), gen_random_uuid(), 'sneaky') $$,
  '42501', null, 'test 32: anon cannot insert an alias');
reset role;

select * from finish();
rollback;
