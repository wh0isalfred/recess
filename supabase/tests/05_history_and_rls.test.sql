-- Tests 12, 13, 14, 15 — history protection, draft deletion, RLS.
begin;
select plan(17);

create temporary table t as select id as event_id from public.events where slug='recess-01';

insert into public.players (phone_e164, real_name) values ('+2348000000021','History Player');
insert into public.event_registrations (event_id, player_id, alias, player_number)
select (select event_id from t), id, 'HISTORY', 1 from public.players;

insert into public.rounds (event_id, event_game_id, room_id, round_index)
select (select event_id from t), eg.id, (select id from public.rooms where label='ROOM 01'), 1
  from public.event_games eg join public.games g on g.id=eg.game_id where g.slug='among-us';

insert into public.results (event_id, round_id, template, payload, idempotency_key)
select (select event_id from t), id, 'ROLE_OUTCOME', '{"winning_role":"impostor"}'::jsonb,
       'idem-history-0001' from public.rounds limit 1;

insert into public.point_transactions (event_id, registration_id, points, source, result_id, round_id)
select (select event_id from t),
       (select id from public.event_registrations where alias='HISTORY'),
       4, 'RESULT', (select id from public.results limit 1), (select id from public.rounds limit 1);

-- ---- test 12: history protection ----------------------------------------
select throws_ok(
  $$ delete from public.events where slug = 'recess-01' $$,
  '23001', null, 'test 12: a non-DRAFT event cannot be deleted');

select throws_ok(
  $$ delete from public.players where phone_e164 = '+2348000000021' $$,
  '23503', null, 'test 12: a player with a registration cannot be deleted');

select throws_ok(
  $$ delete from public.results $$,
  '23001', null, 'test 12: results are append-only');

select throws_ok(
  $$ delete from public.point_transactions $$,
  '23001', null, 'test 12: the ledger is append-only');

select throws_ok(
  $$ update public.point_transactions set points = 99 $$,
  '23001', null, 'test 12: ledger points cannot be edited');

select throws_ok(
  $$ update public.results set payload = '{"winning_role":"crewmate"}'::jsonb $$,
  '23001', null, 'test 12: a result payload cannot be edited in place');

select lives_ok(
  $$ update public.point_transactions
        set voided_at = now(),
            voided_by = null,
            note = note
      where voided_at is null and false $$,
  'test 12: the guard permits a no-op that matches no rows');

insert into public.audit_logs (event_id, action, entity_type, entity_id)
select (select event_id from t), 'test.fixture', 'events', (select event_id from t);
select throws_ok(
  $$ delete from public.audit_logs $$,
  '23001', null, 'test 12: audit logs cannot be deleted');
select throws_ok(
  $$ update public.audit_logs set action = 'tampered' $$,
  '23001', null, 'test 12: audit logs cannot be updated');

select is((select count(*)::int from public.point_transactions), 1,
  'test 12: the ledger row survived every attempt');

-- ---- test 13: draft deletion is permitted -------------------------------
insert into public.events (slug, name, starts_at, capacity)
values ('draft-event','Draft', now() + interval '60 days', 20);
insert into public.rooms (event_id, label, position, capacity)
select id, 'ROOM 01', 1, 10 from public.events where slug='draft-event';
insert into public.event_games (event_id, game_id, position, scoring_template, scoring_config)
select e.id, g.id, 1, g.scoring_template, g.default_scoring_config
  from public.events e cross join public.games g where e.slug='draft-event' and g.slug='trivia';

select lives_ok(
  $$ delete from public.events where slug = 'draft-event' $$,
  'test 13: a DRAFT event can be deleted');
select is((select count(*)::int from public.event_counters
             where event_id not in (select id from public.events)),
  0, 'test 13: no orphan counter row remains');

-- ---- tests 14 and 15: RLS ------------------------------------------------
select is((select count(*)::int from pg_tables
            where schemaname='public' and rowsecurity = false),
  0, 'test 14: row level security is enabled on every table');
select is((select count(*)::int from pg_policies where schemaname='public'),
  0, 'test 14: there are zero policies — deny by default');

set local role anon;
select is((select count(*)::int from public.events), 0,
  'test 14: anon sees zero events');
select is((select count(*)::int from public.point_transactions), 0,
  'test 14: anon sees zero ledger rows');
select throws_ok(
  $$ insert into public.players (phone_e164, real_name) values ('+2348000000099','Anon') $$,
  '42501', null, 'test 14: anon cannot insert');
reset role;

select * from finish();
rollback;
