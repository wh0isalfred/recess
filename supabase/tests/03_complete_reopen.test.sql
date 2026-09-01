-- Test 6c — COMPLETE requires clean rounds; reopening requires a reason.
begin;
select plan(6);

create temporary table t as select id from public.events where slug = 'recess-01';

select public.transition_event((select id from t), 'CHECK_IN');
insert into public.players (phone_e164, real_name) values ('+2348000000001','Test Player');
insert into public.event_registrations (event_id, player_id, alias, player_number, checked_in_at)
  select (select id from t), id, 'TESTER', 1, now() from public.players;
select public.transition_event((select id from t), 'LIVE');

-- A game that is neither complete nor skipped blocks completion.
select throws_ok(
  $$ select public.transition_event((select id from t), 'COMPLETE') $$,
  '23514', null, 'test 6c: cannot complete while a game is still PENDING');

update public.event_games set status = 'COMPLETE' where event_id = (select id from t);
select lives_ok(
  $$ select public.transition_event((select id from t), 'COMPLETE') $$,
  'test 6c: completes once every game is complete or skipped');
select ok((select results_published_at is not null from public.events where slug='recess-01'),
  'test 6c: results_published_at is set on completion');

select throws_ok(
  $$ select public.transition_event((select id from t), 'LIVE') $$,
  '23514', null, 'test 6c: COMPLETE -> LIVE without a reason is refused');

select lives_ok(
  $$ select public.transition_event((select id from t), 'LIVE', 'mis-tapped at 21:40') $$,
  'test 6c: COMPLETE -> LIVE succeeds with a reason');
select ok((select results_published_at is null from public.events where slug='recess-01'),
  'test 6c: results_published_at cleared on reopen');

select * from finish();
rollback;
