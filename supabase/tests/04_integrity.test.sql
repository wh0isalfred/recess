-- Tests 9, 9b, 9c, 9d, 9e, 10, 11 — uniqueness, rooms, cross-event, checks.
begin;
select plan(28);

create temporary table t as select id as event_id from public.events where slug='recess-01';

insert into public.players (phone_e164, real_name, canonical_alias) values
  ('+2348000000011','Alfred Enyinna','WH0ISALFRED'),
  ('+2348000000012','Second Player','DAVO');

create temporary table r as
select
  (select id from public.event_registrations where alias='WH0ISALFRED') as a,
  (select id from public.event_registrations where alias='DAVO') as b;

insert into public.event_registrations (event_id, player_id, alias, player_number)
select (select event_id from t), id, canonical_alias,
       row_number() over (order by phone_e164)
from public.players;

-- ---- test 9: uniqueness violations ---------------------------------------
select throws_ok(
  $$ insert into public.event_registrations (event_id, player_id, alias, player_number)
     values ((select event_id from t),
             (select id from public.players where canonical_alias='DAVO'),
             'SOMEONEELSE', 1) $$,
  '23505', null, 'test 9: duplicate player_number within an event');

select throws_ok(
  $$ insert into public.event_registrations (event_id, player_id, alias, player_number)
     values ((select event_id from t),
             (select id from public.players where canonical_alias='DAVO'),
             'wh0isalfred', 99) $$,
  '23505', null, 'test 9: alias uniqueness is case-insensitive');

select throws_ok(
  $$ insert into public.event_registrations (event_id, player_id, alias, player_number)
     values ((select event_id from t),
             (select id from public.players where canonical_alias='WH0ISALFRED'),
             'SECONDTRY', 98) $$,
  '23505', null, 'test 9: a player cannot register twice for one event');

select throws_ok(
  $$ insert into public.rooms (event_id, label, position, capacity)
     values ((select event_id from t), 'ROOM 01', 9, 15) $$,
  '23505', null, 'test 9: duplicate room label within an event');

select throws_ok(
  $$ insert into public.event_games (event_id, game_id, position, scoring_template, scoring_config)
     select (select event_id from t), id, 1, 'MANUAL', '{"x":1}'::jsonb
       from public.games where slug='skribbl' $$,
  '23505', null, 'test 9: a game cannot appear twice in one event');

-- rounds
insert into public.rounds (event_id, event_game_id, room_id, round_index)
select (select event_id from t), eg.id,
       (select id from public.rooms where label='ROOM 01'), 1
  from public.event_games eg join public.games g on g.id=eg.game_id where g.slug='among-us';

select throws_ok(
  $$ insert into public.rounds (event_id, event_game_id, room_id, round_index)
     select (select event_id from t), eg.id,
            (select id from public.rooms where label='ROOM 01'), 1
       from public.event_games eg join public.games g on g.id=eg.game_id
      where g.slug='among-us' $$,
  '23505', null, 'test 9: duplicate round_index within one room');

select lives_ok(
  $$ insert into public.rounds (event_id, event_game_id, room_id, round_index)
     select (select event_id from t), eg.id,
            (select id from public.rooms where label='ROOM 02'), 1
       from public.event_games eg join public.games g on g.id=eg.game_id
      where g.slug='among-us' $$,
  'test 9: the same round_index in a different room is fine');

-- results: one authoritative result per round
insert into public.results (event_id, round_id, template, payload, idempotency_key)
select (select event_id from t), id, 'ROLE_OUTCOME', '{"winning_role":"impostor"}'::jsonb,
       'idem-key-000001'
  from public.rounds order by created_at limit 1;

select throws_ok(
  $$ insert into public.results (event_id, round_id, template, payload, idempotency_key)
     select (select event_id from t), id, 'ROLE_OUTCOME', '{"winning_role":"crewmate"}'::jsonb,
            'idem-key-000002'
       from public.rounds order by created_at limit 1 $$,
  '23505', null, 'test 9: a second non-superseded result for one round');

select throws_ok(
  $$ insert into public.results (event_id, round_id, template, payload, idempotency_key)
     select (select event_id from t), id, 'ROLE_OUTCOME', '{}'::jsonb, 'idem-key-000001'
       from public.rounds order by created_at desc limit 1 $$,
  '23505', null, 'test 9: idempotency_key is globally unique');

-- ---- test 9b [r3]: Room 01 -> Room 02 -> Room 01 history -----------------
insert into public.room_memberships (event_id, room_id, registration_id, assigned_at, left_at)
select (select event_id from t), (select id from public.rooms where label='ROOM 01'),
       (select id from public.event_registrations where alias='WH0ISALFRED'),
       now() - interval '40 min', now() - interval '25 min';
insert into public.room_memberships (event_id, room_id, registration_id, assigned_at, left_at)
select (select event_id from t), (select id from public.rooms where label='ROOM 02'),
       (select id from public.event_registrations where alias='WH0ISALFRED'),
       now() - interval '25 min', now() - interval '10 min';
select lives_ok(
  $$ insert into public.room_memberships (event_id, room_id, registration_id)
     select (select event_id from t), (select id from public.rooms where label='ROOM 01'),
            (select id from public.event_registrations where alias='WH0ISALFRED') $$,
  'test 9b: returning to a previously left room is legal history');

select is(
  (select count(*)::int from public.room_memberships
    where registration_id = (select id from public.event_registrations where alias='WH0ISALFRED')),
  3, 'test 9b: three membership rows exist');
select is(
  (select count(*)::int from public.room_memberships
    where registration_id = (select id from public.event_registrations where alias='WH0ISALFRED')
      and left_at is null),
  1, 'test 9b: exactly one is active');

-- ---- test 9c [r3]: at most one active membership -------------------------
select throws_ok(
  $$ insert into public.room_memberships (event_id, room_id, registration_id)
     select (select event_id from t), (select id from public.rooms where label='ROOM 02'),
            (select id from public.event_registrations where alias='WH0ISALFRED') $$,
  '23505', null, 'test 9c: a second active membership is rejected');

-- ---- test 9d [r3]: transactional room reorder ---------------------------
savepoint before_reorder;
select lives_ok(
  $$ update public.rooms set position = case position when 1 then 2 else 1 end
      where event_id = (select event_id from t) $$,
  'test 9d: swapping positions in one statement does not raise mid-transaction');
select lives_ok($$ set constraints public.rooms_position_key immediate $$,
  'test 9d: the swap is valid at constraint-check time');
rollback to savepoint before_reorder;

savepoint before_bad_reorder;
set constraints public.rooms_position_key deferred;
update public.rooms set position = 1 where event_id = (select event_id from t);
select throws_ok(
  $$ set constraints public.rooms_position_key immediate $$,
  '23505', null, 'test 9d: an unresolved duplicate still fails at check time');
rollback to savepoint before_bad_reorder;

-- ---- test 9e [r3]: waiting-for-room is derivable -------------------------
update public.event_registrations set checked_in_at = now() where alias = 'DAVO';
select is(
  (select array_agg(er.alias) from public.event_registrations er
    where er.event_id = (select event_id from t)
      and er.checked_in_at is not null
      and not exists (
        select 1 from public.room_memberships rm
         where rm.registration_id = er.id and rm.left_at is null)),
  array['DAVO'],
  'test 9e: checked in with no active membership is derivable without stored state');
select hasnt_column('public','event_registrations','waiting_for_room',
  'test 9e: no column encodes the waiting state');

-- ---- test 10: cross-event integrity --------------------------------------
insert into public.events (slug, name, starts_at, capacity)
values ('other-event','Other', now() + interval '30 days', 10);
insert into public.rooms (event_id, label, position, capacity)
select id, 'ROOM 01', 1, 10 from public.events where slug='other-event';

select throws_ok(
  $$ insert into public.room_memberships (event_id, room_id, registration_id)
     select (select id from public.events where slug='other-event'),
            (select r.id from public.rooms r join public.events e on e.id=r.event_id
              where e.slug='other-event'),
            (select id from public.event_registrations where alias='DAVO') $$,
  '23503', null, 'test 10: event A registration cannot join event B room');

select throws_ok(
  $$ insert into public.rounds (event_id, event_game_id, room_id, round_index)
     select (select event_id from t), eg.id,
            (select r.id from public.rooms r join public.events e on e.id=r.event_id
              where e.slug='other-event'), 7
       from public.event_games eg join public.games g on g.id=eg.game_id
      where g.slug='trivia' $$,
  '23503', null, 'test 10: a round cannot attach to another event''s room');

-- ---- test 11: check constraint violations --------------------------------
select throws_ok($$ insert into public.events (slug,name,starts_at,capacity)
  values ('bad-cap','Bad', now(), 0) $$, '23514', null, 'test 11: capacity must be positive');
select throws_ok($$ insert into public.players (phone_e164, real_name)
  values ('08012345678','Bad Phone') $$, '23514', null, 'test 11: phone must be E.164');
select throws_ok($$ insert into public.games (slug,name,platform,requires_install,scoring_template)
  values ('bad-game','Bad','BROWSER',true,'MANUAL') $$,
  '23514', null, 'test 11: a browser game cannot require an install');
select throws_ok(
  $$ insert into public.round_participants (event_id, round_id, registration_id, participation, role_key)
     select (select event_id from t), (select id from public.rounds order by created_at limit 1),
            (select id from public.event_registrations where alias='DAVO'), 'DNP', 'impostor' $$,
  '23514', null, 'test 11: a DNP participant cannot hold a role');
select throws_ok(
  $$ insert into public.point_transactions (event_id, registration_id, points, source)
     select (select event_id from t),
            (select id from public.event_registrations where alias='DAVO'), 3, 'MANUAL_ADJUSTMENT' $$,
  '23514', null, 'test 11: a manual adjustment requires a note');
select throws_ok(
  $$ insert into public.point_transactions (event_id, registration_id, points, source)
     select (select event_id from t),
            (select id from public.event_registrations where alias='DAVO'), 3, 'RESULT' $$,
  '23514', null, 'test 11: a result transaction requires a result_id');
select throws_ok(
  $$ update public.event_games set scoring_config = '[]'::jsonb
      where event_id = (select event_id from t) $$,
  '23514', null, 'test 11: scoring_config must be a JSON object');
select throws_ok($$ insert into public.events (slug,name,starts_at,capacity,timezone)
  values ('bad-tz','Bad', now(), 10, 'Mars/Olympus') $$,
  '23514', null, 'test 11: timezone must be a real IANA name');

select * from finish();
rollback;
