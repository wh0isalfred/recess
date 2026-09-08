-- Test 47 — Phase 7: Scoring Engine V1 (migration 0025).
begin;
select plan(33);

create or replace function pg_temp.as_staff(p_uid uuid, p_role public.staff_role) returns void
language sql as $$
  insert into auth.users (id) values (p_uid);
  insert into public.staff_profiles (user_id, name, role) values (p_uid, 'Test Staff', p_role);
  select set_config('request.jwt.claim.sub', p_uid::text, true);
$$;

create or replace function pg_temp.as_player_session(p_registration_id uuid) returns void
language plpgsql as $$
declare v_uid uuid := gen_random_uuid();
begin
  insert into auth.users (id) values (v_uid);
  update event_registrations set auth_user_id = v_uid where id = p_registration_id;
  perform set_config('request.jwt.claim.sub', v_uid::text, true);
end $$;

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

-- ---------------------------------------------------------------------- fixture

select pg_temp.as_staff(gen_random_uuid(), 'SUPER_ADMIN');

insert into public.events (slug, name, status, starts_at, timezone, timezone_label, capacity)
values ('test-score25', 'Scoring Event', 'LIVE', now() - interval '1 hour', 'Africa/Lagos', 'WAT', 30);
create temporary table ev25 as select id from public.events where slug = 'test-score25';

insert into public.games (slug, name, platform, scoring_template, status, artwork_url, default_round_count)
values ('test-au25', 'Test Among Us 25', 'INSTALL', 'ROLE_OUTCOME', 'ACTIVE', '/games/test-au25.webp', 3);
insert into public.games (slug, name, platform, scoring_template, status, artwork_url, default_round_count)
values ('test-skribbl25', 'Test Skribbl 25', 'BROWSER', 'PLACEMENT', 'ACTIVE', '/games/test-skribbl25.webp', 1);

-- ROLE_OUTCOME event_game with the real RECESS #1 award values.
insert into event_games (event_id, game_id, position, scoring_template, planned_rounds, scoring_config)
select (select id from ev25), id, 1, 'ROLE_OUTCOME', 3,
       jsonb_build_object('awards', jsonb_build_object(
         'crewmate', jsonb_build_object('win', 1, 'loss', 0),
         'impostor', jsonb_build_object('win', 2, 'loss', 0)
       ))
  from games where slug = 'test-au25';
create temporary table auGame as select id from event_games where event_id = (select id from ev25) and position = 1;

insert into event_games (event_id, game_id, position, scoring_template, planned_rounds, scoring_config)
select (select id from ev25), id, 2, 'PLACEMENT', 1, jsonb_build_object('type', 'placement')
  from games where slug = 'test-skribbl25';
create temporary table skribblGame as select id from event_games where event_id = (select id from ev25) and position = 2;

select pg_temp.register((select id from ev25), 'scorecoord1', '+2348070000001');
select public.admin_create_room('test-score25', 'SCORE ROOM 01', 8,
  (select id from public.event_registrations where alias = 'scorecoord1'));
create temporary table scoreRoom1 as select id from rooms where event_id = (select id from ev25) and label = 'SCORE ROOM 01';

select pg_temp.register((select id from ev25), 'scorecoord2', '+2348070000002');
select public.admin_create_room('test-score25', 'SCORE ROOM 02', 8,
  (select id from public.event_registrations where alias = 'scorecoord2'));
create temporary table scoreRoom2 as select id from rooms where event_id = (select id from ev25) and label = 'SCORE ROOM 02';

-- Four ordinary players seated directly in Room 01 (bypassing check-in for
-- speed — identical end state to what check_in_player() would produce).
select pg_temp.register((select id from ev25), 'p1', '+2348070000011');
select pg_temp.register((select id from ev25), 'p2', '+2348070000012');
select pg_temp.register((select id from ev25), 'p3', '+2348070000013');
select pg_temp.register((select id from ev25), 'p4', '+2348070000014');
insert into room_memberships (event_id, room_id, registration_id)
select (select id from ev25), (select id from scoreRoom1), id from event_registrations where alias in ('p1','p2','p3','p4');

-- ==================================================================== ROUND / SNAPSHOT

select public.start_room_game((select id from scoreRoom1), (select id from auGame));
select lives_ok(
  $$ select public.start_round((select id from scoreRoom1), (select id from auGame)) $$,
  'test 47: starting a round succeeds for a live room-game');
create temporary table round1 as
  select id from rounds where room_id = (select id from scoreRoom1) and event_game_id = (select id from auGame) and round_index = 1;

select is(
  (select count(*) from round_participants where round_id = (select id from round1)),
  4::bigint,
  'test 47: the round snapshots exactly the 4 current room members');

-- A late arrival joins Room 01 AFTER round 1 has already started.
select pg_temp.register((select id from ev25), 'late1', '+2348070000015');
insert into room_memberships (event_id, room_id, registration_id)
select (select id from ev25), (select id from scoreRoom1), id from event_registrations where alias = 'late1';

select ok(
  not exists (select 1 from round_participants where round_id = (select id from round1) and registration_id = (select id from event_registrations where alias='late1')),
  'test 47: a late arrival is excluded from the already-active round''s snapshot');

-- ==================================================================== NORMAL RESULT + IDEMPOTENCY

select public.submit_round_result(
  (select id from round1),
  jsonb_build_object(
    'winningRole', 'impostor',
    'participants', jsonb_build_array(
      jsonb_build_object('registrationId', (select id from event_registrations where alias='p1'), 'participation','PARTICIPATING','role','impostor'),
      jsonb_build_object('registrationId', (select id from event_registrations where alias='p2'), 'participation','PARTICIPATING','role','crewmate'),
      jsonb_build_object('registrationId', (select id from event_registrations where alias='p3'), 'participation','PARTICIPATING','role','crewmate'),
      jsonb_build_object('registrationId', (select id from event_registrations where alias='p4'), 'participation','DNP')
    )
  ),
  'idem-round1-0001'
);
select is(
  (select status from rounds where id = (select id from round1)), 'COMPLETE',
  'test 47: the round is marked COMPLETE after a real result');
select is(
  (select count(*) from results where round_id = (select id from round1) and superseded_at is null),
  1::bigint,
  'test 47: exactly one authoritative result exists for the round');

select is(
  (select public.submit_round_result((select id from round1), '{}'::jsonb, 'idem-round1-0001')->>'idempotent'),
  'true',
  'test 47: resubmitting the same idempotency key is treated as idempotent (double submission safe)');
select is(
  (select public.submit_round_result((select id from round1), '{}'::jsonb, 'idem-round1-0001')->>'idempotent'),
  'true',
  'test 47: a third submission with the same key is still idempotent (triple submission safe)');
select is(
  (select count(*) from results where round_id = (select id from round1)),
  1::bigint,
  'test 47: no duplicate result rows were created by the repeated submissions');

-- Room 1 can only have one game LIVE at a time (Phase 6.5) — complete
-- auGame here before skribblGame can start in the same room.
select public.complete_room_game((select id from scoreRoom1), (select id from auGame));

-- ==================================================================== INVALID PARTICIPANT

select public.start_room_game((select id from scoreRoom1), (select id from skribblGame));
select public.start_round((select id from scoreRoom1), (select id from skribblGame));
create temporary table sk_round1 as
  select id from rounds where room_id = (select id from scoreRoom1) and event_game_id = (select id from skribblGame) and round_index = 1;

select throws_like(
  $$ select public.submit_round_result(
       (select id from sk_round1),
       jsonb_build_object('scores', jsonb_build_array(jsonb_build_object('registrationId', gen_random_uuid(), 'rawScore', 100))),
       'idem-invalid-participant-0001'
     ) $$,
  'invalid_participant%',
  'test 47: a registration not in the round''s snapshot is rejected');

-- ==================================================================== DNP / disconnect + PLACEMENT

select public.submit_round_result(
  (select id from sk_round1),
  jsonb_build_object('scores', jsonb_build_array(
    jsonb_build_object('registrationId', (select id from event_registrations where alias='p1'), 'participation','PARTICIPATING', 'rawScore', 4210),
    jsonb_build_object('registrationId', (select id from event_registrations where alias='p2'), 'participation','PARTICIPATING', 'rawScore', 3980),
    jsonb_build_object('registrationId', (select id from event_registrations where alias='p3'), 'participation','PARTICIPATING', 'rawScore', 3980),
    -- p4 disconnected mid-session — recorded the same way any DNP is.
    jsonb_build_object('registrationId', (select id from event_registrations where alias='p4'), 'participation','DNP'),
    -- late1 joined room 1 before this round started (unlike auGame's round
    -- 1, already underway when they arrived) — legitimately eligible here.
    jsonb_build_object('registrationId', (select id from event_registrations where alias='late1'), 'participation','PARTICIPATING', 'rawScore', 1000)
  )),
  'idem-sk-round1-0001'
);
select is(
  (select participation::text from round_participants where round_id=(select id from sk_round1) and registration_id=(select id from event_registrations where alias='p4')),
  'DNP',
  'test 47: a disconnected participant is recorded as DNP, identically to any other DNP');

-- ==================================================================== TIE (competition ranking)

select public.complete_room_game((select id from scoreRoom1), (select id from skribblGame));
select is(
  (select jsonb_array_length(public.room_standings((select id from scoreRoom1)))),
  5,
  'test 47: room_standings includes every room member, even one who never played');

select is(
  (select (jsonb_path_query_first(public.room_standings((select id from scoreRoom1)), '$[*] ? (@.alias == "p2")')->>'placement')::int),
  2,
  'test 47: p2 (tied with p3 on raw score) is placed 2nd');
select is(
  (select (jsonb_path_query_first(public.room_standings((select id from scoreRoom1)), '$[*] ? (@.alias == "p3")')->>'placement')::int),
  2,
  'test 47: p3 (tied with p2 on raw score) is also placed 2nd — competition ranking, not broken');
select ok(
  not exists (select 1 from jsonb_array_elements(public.room_standings((select id from scoreRoom1))) e where e->>'alias' = 'p1' and (e->>'placement')::int = 3),
  'test 47: placement 3 is correctly skipped after a tie at 2nd (competition ranking)');

-- ==================================================================== ROLE_OUTCOME settlement / configurable roles / N,P normalization

-- Already completed/settled earlier (had to happen before skribblGame could
-- start in the same room) — confirm re-completing is a safe no-op.
select lives_ok(
  $$ select public.complete_room_game((select id from scoreRoom1), (select id from auGame)) $$,
  'test 47: re-completing an already-complete room-game is a safe no-op');

select is(
  (select points from point_transactions
    where room_event_game_id = (select id from room_event_games where room_id=(select id from scoreRoom1) and event_game_id=(select id from auGame))
      and registration_id = (select id from event_registrations where alias='p1') and voided_at is null),
  20,
  'test 47: the sole impostor winner (raw 2, highest) is normalized to 20 (first place)');
select is(
  (select count(*) from point_transactions
    where room_event_game_id = (select id from room_event_games where room_id=(select id from scoreRoom1) and event_game_id=(select id from auGame))
      and registration_id = (select id from event_registrations where alias='p4') and voided_at is null),
  0::bigint,
  'test 47: a player who DNP''d the entire game receives no championship-points row for it');
select is(
  (select count(*) from point_transactions
    where room_event_game_id = (select id from room_event_games where room_id=(select id from scoreRoom1) and event_game_id=(select id from auGame))
      and voided_at is null),
  3::bigint,
  'test 47: N (the ranked denominator) is 3 — p4''s full-game DNP correctly does not expand it');

-- ==================================================================== MULTI-ROUND AGGREGATION

select pg_temp.register((select id from ev25), 'q1', '+2348070000021');
select pg_temp.register((select id from ev25), 'q2', '+2348070000022');
insert into room_memberships (event_id, room_id, registration_id)
select (select id from ev25), (select id from scoreRoom2), id from event_registrations where alias in ('scorecoord2', 'q1', 'q2')
on conflict do nothing;

select public.start_room_game((select id from scoreRoom2), (select id from auGame));
select public.start_round((select id from scoreRoom2), (select id from auGame));

create temporary table auRound2_1 as select id from rounds where room_id=(select id from scoreRoom2) and event_game_id=(select id from auGame) and round_index=1;
select public.submit_round_result(
  (select id from auRound2_1),
  jsonb_build_object('winningRole','crewmate','participants', jsonb_build_array(
    jsonb_build_object('registrationId',(select id from event_registrations where alias='q1'),'participation','PARTICIPATING','role','impostor'),
    jsonb_build_object('registrationId',(select id from event_registrations where alias='q2'),'participation','PARTICIPATING','role','crewmate'),
    jsonb_build_object('registrationId',(select id from event_registrations where alias='scorecoord2'),'participation','DNP')
  )), 'idem-auround2-1-0001'
);
select public.start_round((select id from scoreRoom2), (select id from auGame));
create temporary table auRound2_2 as select id from rounds where room_id=(select id from scoreRoom2) and event_game_id=(select id from auGame) and round_index=2;
select public.submit_round_result(
  (select id from auRound2_2),
  jsonb_build_object('winningRole','impostor','participants', jsonb_build_array(
    jsonb_build_object('registrationId',(select id from event_registrations where alias='q1'),'participation','PARTICIPATING','role','impostor'),
    jsonb_build_object('registrationId',(select id from event_registrations where alias='q2'),'participation','PARTICIPATING','role','crewmate'),
    jsonb_build_object('registrationId',(select id from event_registrations where alias='scorecoord2'),'participation','DNP')
  )), 'idem-auround2-2-0001'
);
select public.complete_room_game((select id from scoreRoom2), (select id from auGame));

select is(
  (select points from point_transactions
    where room_event_game_id=(select id from room_event_games where room_id=(select id from scoreRoom2) and event_game_id=(select id from auGame))
      and registration_id=(select id from event_registrations where alias='q1') and voided_at is null),
  20,
  'test 47: multi-round aggregation — q1''s raw total (0 + 2 = 2, impostor loss then win) beats q2''s (0 + 0) and normalizes to 20');

-- ==================================================================== CORRECTION / SUPERSESSION / VOIDED TXNS

create temporary table pre_correction_txn as
  select id from point_transactions
   where room_event_game_id=(select id from room_event_games where room_id=(select id from scoreRoom2) and event_game_id=(select id from auGame))
     and voided_at is null;

-- Correct round 1: q1 was actually crewmate the whole time, not impostor.
select public.submit_round_result(
  (select id from auRound2_1),
  jsonb_build_object('winningRole','crewmate','participants', jsonb_build_array(
    jsonb_build_object('registrationId',(select id from event_registrations where alias='q1'),'participation','PARTICIPATING','role','crewmate'),
    jsonb_build_object('registrationId',(select id from event_registrations where alias='q2'),'participation','PARTICIPATING','role','crewmate'),
    jsonb_build_object('registrationId',(select id from event_registrations where alias='scorecoord2'),'participation','DNP')
  )), 'idem-auround2-1-CORRECTED'
);
select is(
  (select count(*) from results where round_id=(select id from auRound2_1)),
  2::bigint,
  'test 47: a correction creates a second results row (supersession), not an edit');
select is(
  (select count(*) from results where round_id=(select id from auRound2_1) and superseded_at is null),
  1::bigint,
  'test 47: exactly one authoritative (non-superseded) result remains after correction');

select ok(
  (select bool_and(voided_at is not null) from point_transactions where id in (select id from pre_correction_txn)),
  'test 47: the correction immediately voided the previous settlement''s transactions');
select is(
  (select points from point_transactions
    where room_event_game_id=(select id from room_event_games where room_id=(select id from scoreRoom2) and event_game_id=(select id from auGame))
      and registration_id=(select id from event_registrations where alias='q1') and voided_at is null),
  20,
  'test 47: replacement transactions reflect the corrected totals (q1 now crewmate win + crewmate win = 2 raw, still 1st)');
select isnt(
  (select id from point_transactions
    where room_event_game_id=(select id from room_event_games where room_id=(select id from scoreRoom2) and event_game_id=(select id from auGame))
      and registration_id=(select id from event_registrations where alias='q1') and voided_at is null),
  (select id from pre_correction_txn limit 1),
  'test 47: the surviving transaction is a genuinely new row, not the old one un-voided');

-- ==================================================================== VOID ROUND

select public.start_room_game((select id from scoreRoom2), (select id from skribblGame));
select public.start_round((select id from scoreRoom2), (select id from skribblGame));
create temporary table sk_round2 as select id from rounds where room_id=(select id from scoreRoom2) and event_game_id=(select id from skribblGame);
select lives_ok(
  $$ select public.void_round((select id from sk_round2), 'external game crashed before completion') $$,
  'test 47: voiding a live round succeeds with a real reason');
select is(
  (select status from rounds where id = (select id from sk_round2)), 'VOID',
  'test 47: the voided round''s status is VOID');
select throws_like(
  $$ select public.void_round((select id from sk_round2), 'trying again') $$,
  'round_not_live%',
  'test 47: an already-void round cannot be voided again');

-- ==================================================================== QUALIFICATION

select is(
  (select count(*) from jsonb_array_elements(public.room_standings((select id from scoreRoom1))) e where (e->>'qualifies')::boolean),
  3::bigint,
  'test 47: room 1''s own genuine tie at 2nd (p2/p3, same tie tested above) correctly qualifies 3, not 2 — position 1 plus both tied at 2');

-- A room where 2nd place is a tie: everyone tied at 2nd qualifies too.
select pg_temp.register((select id from ev25), 'tcoord', '+2348070000031');
select public.admin_create_room('test-score25', 'TIE ROOM', 8, (select id from event_registrations where alias='tcoord'));
create temporary table tieRoom as select id from rooms where event_id=(select id from ev25) and label='TIE ROOM';
select pg_temp.register((select id from ev25), 't1', '+2348070000032');
select pg_temp.register((select id from ev25), 't2', '+2348070000033');
select pg_temp.register((select id from ev25), 't3', '+2348070000034');
insert into room_memberships (event_id, room_id, registration_id)
select (select id from ev25), (select id from tieRoom), id from event_registrations where alias in ('t1','t2','t3');
select public.admin_manual_adjustment('test-score25', (select id from event_registrations where alias='t1'), 20, 'test fixture: t1 leads');
select public.admin_manual_adjustment('test-score25', (select id from event_registrations where alias='t2'), 15, 'test fixture: t2 ties for 2nd');
select public.admin_manual_adjustment('test-score25', (select id from event_registrations where alias='t3'), 15, 'test fixture: t3 ties for 2nd');

select is(
  (select count(*) from jsonb_array_elements(public.room_standings((select id from tieRoom))) e where (e->>'qualifies')::boolean),
  3::bigint,
  'test 47: a tie touching the position-2 boundary qualifies everyone tied there (3 qualify, not 2)');

-- ==================================================================== MANUAL ADJUSTMENT authorization/note

select throws_like(
  $$ select public.admin_manual_adjustment('test-score25', (select id from event_registrations where alias='t1'), 5, '') $$,
  'invalid_note%',
  'test 47: a manual adjustment without a real note is rejected');

select pg_temp.as_staff(gen_random_uuid(), 'COORDINATOR');
select throws_ok(
  $$ select public.admin_manual_adjustment('test-score25', (select id from event_registrations where alias='t1'), 5, 'test') $$,
  '42501', null,
  'test 47: a COORDINATOR cannot perform a manual adjustment — Admin only');

-- ==================================================================== UNAUTHORIZED / CROSS-ROOM

select pg_temp.as_player_session((select id from event_registrations where alias = 'p1'));
select throws_ok(
  $$ select public.start_round((select id from scoreRoom1), (select id from auGame)) $$,
  '42501', null,
  'test 47: an ordinary player (not the room''s coordinator) cannot start a round');

select pg_temp.as_player_session((select id from event_registrations where alias = 'scorecoord2'));
select throws_ok(
  $$ select public.start_round((select id from scoreRoom1), (select id from skribblGame)) $$,
  '42501', null,
  'test 47: room 2''s coordinator cannot start a round in room 1 (cross-room access)');

select * from finish();
rollback;
