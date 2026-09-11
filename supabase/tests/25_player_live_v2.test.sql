-- Test 54 — Phase 8.3 Gate B: Player Live V2 room-stage (migration 0032).
begin;
select plan(36);

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

select pg_temp.as_staff(gen_random_uuid(), 'SUPER_ADMIN');

insert into public.events (
  slug, name, status, starts_at, timezone, timezone_label,
  registration_opens_at, registration_closes_at, capacity,
  checkin_opens_at, checkin_closes_at, leaderboard_visibility
) values (
  'test-live54', 'Live V2 Event', 'REGISTRATION', now() + interval '2 days', 'Africa/Lagos', 'WAT',
  now() - interval '1 day', now() + interval '30 days', 30,
  now() - interval '2 hours', now() + interval '2 hours', 'LIVE'
);
create temporary table ev54 as select id from public.events where slug = 'test-live54';

insert into public.games (slug, name, platform, scoring_template, status, artwork_url, platform_url, default_round_count)
values ('test-au54', 'Test Among Us 54', 'INSTALL', 'ROLE_OUTCOME', 'ACTIVE', '/games/test-au54.webp', null, 3);
insert into event_games (event_id, game_id, position, scoring_template, planned_rounds, duration_minutes, scoring_config)
select (select id from ev54), id, 1, 'ROLE_OUTCOME', 3, null,
       jsonb_build_object('awards', jsonb_build_object(
         'crewmate', jsonb_build_object('win', 1, 'loss', 0),
         'impostor', jsonb_build_object('win', 2, 'loss', 0)
       ))
  from games where slug = 'test-au54';
create temporary table auGame54 as select id from event_games where event_id = (select id from ev54) and position = 1;

insert into public.games (slug, name, platform, scoring_template, status, artwork_url, platform_url, default_round_count)
values ('test-sk54', 'Test Skribbl 54', 'BROWSER', 'PLACEMENT', 'ACTIVE', '/games/test-sk54.webp', 'https://skribbl.example', 1);
insert into event_games (event_id, game_id, position, scoring_template, planned_rounds, duration_minutes, scoring_config)
select (select id from ev54), id, 2, 'PLACEMENT', 1, null, jsonb_build_object('type','placement')
  from games where slug = 'test-sk54';
create temporary table skGame54 as select id from event_games where event_id = (select id from ev54) and position = 2;

select pg_temp.register((select id from ev54), 'lvcoord', '+2348130000001');
create temporary table reg_lvcoord as select id from event_registrations where alias='lvcoord';
select public.admin_create_room('test-live54', 'LIVE ROOM 01', 3, (select id from reg_lvcoord));
create temporary table lvroom as select id from rooms where event_id = (select id from ev54) and label = 'LIVE ROOM 01';

select pg_temp.register((select id from ev54), 'lv1', '+2348130000011');
select pg_temp.register((select id from ev54), 'lv2', '+2348130000012');
select pg_temp.register((select id from ev54), 'lv3', '+2348130000013');
create temporary table reg_lv1 as select id from event_registrations where alias='lv1';
create temporary table reg_lv2 as select id from event_registrations where alias='lv2';
create temporary table reg_lv3 as select id from event_registrations where alias='lv3';

-- ==================================================================== 1. PASS_COUNTDOWN unchanged

-- (created as REGISTRATION already, above)
select pg_temp.as_player_session((select id from reg_lv1));
select is(
  (select (public.get_player_state()->>'view')),
  'PASS_COUNTDOWN',
  'test 54: PASS_COUNTDOWN remains unchanged for a registered, unregistered-for-checkin player');

-- ==================================================================== 2+3. CHECK_IN_OPEN then CHECKED_IN_WAITING

select pg_temp.as_staff(gen_random_uuid(), 'SUPER_ADMIN');
select public.transition_event((select id from ev54), 'CHECK_IN');
select pg_temp.as_player_session((select id from reg_lv1));
select is(
  (select (public.get_player_state()->>'view')),
  'CHECK_IN_OPEN',
  'test 54: CHECK_IN_OPEN is correct before checking in');

-- lv1 and lv2 check in and exactly fill the room's capacity of 2 via
-- ordinary sequential fill. lv3 checks in next, genuinely finding no
-- capacity left — a real "checked in, no room" latecomer, not a
-- contrived one.
select public.check_in_player();
select pg_temp.as_player_session((select id from reg_lv2));
select public.check_in_player();
select pg_temp.as_player_session((select id from reg_lv3));
select public.check_in_player();

select pg_temp.as_staff(gen_random_uuid(), 'SUPER_ADMIN');
select public.transition_event((select id from ev54), 'LIVE');

select pg_temp.as_player_session((select id from reg_lv3));
select is(
  (select (public.get_player_state()->>'view')),
  'CHECKED_IN_WAITING',
  'test 54: a latecomer checking in after the room is genuinely full -> CHECKED_IN_WAITING');

-- ==================================================================== 4. ROOM_ASSIGNED before first game

select pg_temp.as_player_session((select id from reg_lv1));
select is(
  (select (public.get_player_state()->>'view')),
  'ROOM_ASSIGNED',
  'test 54: assigned room before first game -> ROOM_ASSIGNED');
select is(
  (select (public.get_player_state()->'nextGame'->>'slug')),
  'test-au54',
  'test 54: ROOM_ASSIGNED correctly names the first configured game as nextGame');
select is(
  (select (public.get_player_state()->'upFirstGame'->>'slug')),
  'test-au54',
  'test 54: the deprecated upFirstGame compatibility field is still populated identically during the deployment window');

-- ==================================================================== 5. LIVE_ROUND

select pg_temp.as_staff(gen_random_uuid(), 'SUPER_ADMIN');
select public.start_room_game((select id from lvroom), (select id from auGame54));
select public.start_round((select id from lvroom), (select id from auGame54));

select pg_temp.as_player_session((select id from reg_lv1));
select is(
  (select (public.get_player_state()->>'view')),
  'LIVE_ROUND',
  'test 54: first room game LIVE + round LIVE -> LIVE_ROUND');
select is(
  (select (public.get_player_state()->'activeGame'->'liveRound'->>'roundIndex')::int),
  1,
  'test 54: activeGame.liveRound.roundIndex is correct');

-- ==================================================================== 6. BETWEEN_ROUNDS, awaitingGameSettlement=false

select pg_temp.as_staff(gen_random_uuid(), 'SUPER_ADMIN');
create temporary table au54round1 as select id from rounds where room_id=(select id from lvroom) and event_game_id=(select id from auGame54) and round_index=1;
select public.submit_round_result(
  (select id from au54round1),
  jsonb_build_object('winningRole','crewmate','participants', jsonb_build_array(
    jsonb_build_object('registrationId',(select id from reg_lv1),'participation','PARTICIPATING','role','crewmate'),
    jsonb_build_object('registrationId',(select id from reg_lv2),'participation','PARTICIPATING','role','impostor')
  )), 'idem-au54r1-0001'
);

select pg_temp.as_player_session((select id from reg_lv1));
select is(
  (select (public.get_player_state()->>'view')),
  'BETWEEN_ROUNDS',
  'test 54: confirmed round with more rounds remaining -> BETWEEN_ROUNDS');
select is(
  (select (public.get_player_state()->'activeGame'->>'awaitingGameSettlement')),
  'false',
  'test 54: awaitingGameSettlement is false with 1 of 3 rounds done and no window configured');
select is(
  (select (public.get_player_state()->'activeGame'->'lastRoundResult'->'yourFact'->>'role')),
  'crewmate',
  'test 54: the caller''s own confirmed fact is correctly exposed');
select ok(
  not (public.get_player_state()->'activeGame'->'lastRoundResult' ? 'yourPointsThisRound'),
  'test 54: no yourPointsThisRound field exists anywhere in the payload');

-- ==================================================================== 9. VOID rounds do not count

select pg_temp.as_staff(gen_random_uuid(), 'SUPER_ADMIN');
select public.start_round((select id from lvroom), (select id from auGame54));
create temporary table au54round2void as select id from rounds where room_id=(select id from lvroom) and event_game_id=(select id from auGame54) and round_index=2;
select public.void_round((select id from au54round2void), 'test fixture: simulate a crash');

select pg_temp.as_player_session((select id from reg_lv1));
select is(
  (select (public.get_player_state()->'activeGame'->>'awaitingGameSettlement')),
  'false',
  'test 54: a VOID round does not count toward the planned-round completion — still not ready to settle');

-- ==================================================================== 7. final round confirmed -> awaitingGameSettlement=true

select pg_temp.as_staff(gen_random_uuid(), 'SUPER_ADMIN');
select public.start_round((select id from lvroom), (select id from auGame54));
create temporary table au54round3 as select id from rounds where room_id=(select id from lvroom) and event_game_id=(select id from auGame54) and round_index=3;
select public.submit_round_result(
  (select id from au54round3),
  jsonb_build_object('winningRole','crewmate','participants', jsonb_build_array(
    jsonb_build_object('registrationId',(select id from reg_lv1),'participation','PARTICIPATING','role','crewmate'),
    jsonb_build_object('registrationId',(select id from reg_lv2),'participation','PARTICIPATING','role','impostor')
  )), 'idem-au54r3-0001'
);

select pg_temp.as_player_session((select id from reg_lv1));
select is(
  (select (public.get_player_state()->>'view')),
  'BETWEEN_ROUNDS',
  'test 54: round 3 confirmed (2 of 3 real completions so far — round 2 was voided) still shows BETWEEN_ROUNDS');
select is(
  (select (public.get_player_state()->'activeGame'->>'awaitingGameSettlement')),
  'false',
  'test 54: still not ready — only 2 of 3 planned rounds are genuinely complete (the void doesn''t count, but doesn''t grant early credit either)');

-- A real fourth round (replacing the voided one) is what actually reaches
-- 3 genuine completions.
select pg_temp.as_staff(gen_random_uuid(), 'SUPER_ADMIN');
select public.start_round((select id from lvroom), (select id from auGame54));
create temporary table au54round4 as select id from rounds where room_id=(select id from lvroom) and event_game_id=(select id from auGame54) and round_index=4;
select public.submit_round_result(
  (select id from au54round4),
  jsonb_build_object('winningRole','crewmate','participants', jsonb_build_array(
    jsonb_build_object('registrationId',(select id from reg_lv1),'participation','PARTICIPATING','role','crewmate'),
    jsonb_build_object('registrationId',(select id from reg_lv2),'participation','PARTICIPATING','role','impostor')
  )), 'idem-au54r4-0001'
);

select pg_temp.as_player_session((select id from reg_lv1));
select is(
  (select (public.get_player_state()->>'view')),
  'BETWEEN_ROUNDS',
  'test 54: the genuine third completion still shows BETWEEN_ROUNDS, not a new state');
select is(
  (select (public.get_player_state()->'activeGame'->>'awaitingGameSettlement')),
  'true',
  'test 54: awaitingGameSettlement is true once completedRounds genuinely reaches plannedRounds with no live round');
select ok(
  not (public.get_player_state()->'activeGame' ? 'yourGamePoints'),
  'test 54: yourGamePoints does not appear anywhere on activeGame before settlement');

-- ==================================================================== 10+11. settlement makes points visible

select pg_temp.as_staff(gen_random_uuid(), 'SUPER_ADMIN');
select public.complete_room_game((select id from lvroom), (select id from auGame54));

select pg_temp.as_player_session((select id from reg_lv1));
select is(
  (select (public.get_player_state()->>'view')),
  'BETWEEN_GAMES',
  'test 54: complete_room_game() succeeding moves the player to BETWEEN_GAMES');
select is(
  (select (public.get_player_state()->'lastCompletedGame'->>'yourGamePoints')::numeric),
  20::numeric,
  'test 54: yourGamePoints is now present and correct (crewmate win x2 = 20, competition-ranked and normalized)');
select is(
  (select (public.get_player_state()->'nextGame'->>'slug')),
  'test-sk54',
  'test 54: BETWEEN_GAMES correctly names the next configured game');

-- ==================================================================== 12. room_event_game_id grouping correctness

select pg_temp.as_staff(gen_random_uuid(), 'SUPER_ADMIN');
select public.start_room_game((select id from lvroom), (select id from skGame54));
select public.start_round((select id from lvroom), (select id from skGame54));
create temporary table sk54round1 as select id from rounds where room_id=(select id from lvroom) and event_game_id=(select id from skGame54) and round_index=1;
select public.submit_round_result(
  (select id from sk54round1),
  jsonb_build_object('scores', jsonb_build_array(
    jsonb_build_object('registrationId',(select id from reg_lv1),'participation','PARTICIPATING','rawScore',100),
    jsonb_build_object('registrationId',(select id from reg_lv2),'participation','PARTICIPATING','rawScore',50)
  )), 'idem-sk54r1-0001'
);
select public.complete_room_game((select id from lvroom), (select id from skGame54));

select pg_temp.as_player_session((select id from reg_lv1));
select is(
  (select (public.get_player_state()->'lastCompletedGame'->>'yourGamePoints')::numeric),
  20::numeric,
  'test 54: Skribbl''s settled points (a DIFFERENT room_event_game) are correctly scoped, not mixed with Among Us''s own 20');

-- ==================================================================== 8. duration-expired game with fewer than planned rounds

-- A separate, dedicated game (position 3 — reached only after skGame54,
-- position 2, is genuinely complete, matching Phase 6.5's game-order
-- rule) for this assertion only.
select pg_temp.as_staff(gen_random_uuid(), 'SUPER_ADMIN');
insert into public.games (slug, name, platform, scoring_template, status, artwork_url, default_round_count)
values ('test-tv54', 'Test Trivia 54', 'BROWSER', 'PLACEMENT', 'ACTIVE', '/games/test-tv54.webp', 5);
insert into event_games (event_id, game_id, position, scoring_template, planned_rounds, duration_minutes, scoring_config)
select (select id from ev54), id, 3, 'PLACEMENT', 5, 10, jsonb_build_object('type','placement')
  from games where slug = 'test-tv54';
create temporary table tvGame54 as select id from event_games where event_id=(select id from ev54) and position=3;
select public.start_room_game((select id from lvroom), (select id from tvGame54));
update room_event_games set started_at = now() - interval '999 hours'
 where room_id = (select id from lvroom) and event_game_id = (select id from tvGame54);

select pg_temp.as_player_session((select id from reg_lv1));
select is(
  (select (public.get_player_state()->>'view')),
  'BETWEEN_ROUNDS',
  'test 54: a game with an expired duration window and zero completed rounds is BETWEEN_ROUNDS (not LIVE_ROUND)');
select is(
  (select (public.get_player_state()->'activeGame'->>'awaitingGameSettlement')),
  'true',
  'test 54: awaitingGameSettlement is true purely from an expired duration window, with fewer than planned rounds completed and no live round');

select pg_temp.as_staff(gen_random_uuid(), 'SUPER_ADMIN');
select public.complete_room_game((select id from lvroom), (select id from tvGame54));

-- ==================================================================== 13/14/15/16 qualification

select pg_temp.as_player_session((select id from reg_lv1));
select is(
  (select (public.get_player_state()->>'view')),
  'QUALIFIED',
  'test 54: the room''s last configured game completing derives qualification for a 2-player room (both in the top-2 boundary)');
select is(
  (select (public.get_player_state()->'championship'->>'yourTotalPoints')::numeric),
  40::numeric,
  'test 54: championship.yourTotalPoints correctly sums both settled games (20 + 20)');

select pg_temp.as_player_session((select id from reg_lv2));
select is(
  (select (public.get_player_state()->>'view')),
  'QUALIFIED',
  'test 54: the second player in this 2-person room also qualifies (both within the top-2 boundary)');

-- ==================================================================== 17+18. PAUSED and resume

select pg_temp.as_staff(gen_random_uuid(), 'SUPER_ADMIN');
select public.transition_event((select id from ev54), 'PAUSED');
select pg_temp.as_player_session((select id from reg_lv1));
select is(
  (select (public.get_player_state()->>'view')),
  'PAUSED',
  'test 54: a paused event overrides the player''s otherwise-normal state');

select pg_temp.as_staff(gen_random_uuid(), 'SUPER_ADMIN');
select public.transition_event((select id from ev54), 'LIVE');
select pg_temp.as_player_session((select id from reg_lv1));
select is(
  (select (public.get_player_state()->>'view')),
  'QUALIFIED',
  'test 54: resuming recomputes the correct underlying state, not a stuck PAUSED');

-- ==================================================================== 19/21/22 leaderboard visibility

select pg_temp.as_staff(gen_random_uuid(), 'SUPER_ADMIN');
update public.events set leaderboard_visibility = 'HIDDEN_UNTIL_FINALE' where id = (select id from ev54);
select pg_temp.as_player_session((select id from reg_lv1));
select is(
  (select (public.get_player_state()->'championship'->>'roomPlacement')),
  null,
  'test 54: HIDDEN_UNTIL_FINALE hides comparative room placement throughout the room stage');
select is(
  (select (public.get_player_state()->'championship'->>'yourTotalPoints')::numeric),
  40::numeric,
  'test 54: HIDDEN_UNTIL_FINALE still shows the player''s own total points — hiding is comparative-only');

select pg_temp.as_staff(gen_random_uuid(), 'SUPER_ADMIN');
update public.events set leaderboard_visibility = 'LIVE' where id = (select id from ev54);
select pg_temp.as_player_session((select id from reg_lv1));
select isnt(
  (select (public.get_player_state()->'championship'->>'roomPlacement')),
  null,
  'test 54: leaderboard_visibility=LIVE exposes comparative room placement once permitted');

-- ==================================================================== 25/26. pending correction and approval

select pg_temp.as_staff(gen_random_uuid(), 'SUPER_ADMIN');
insert into public.events (slug, name, status, starts_at, timezone, timezone_label, capacity, leaderboard_visibility)
values ('test-live54b', 'Live V2 Event B', 'LIVE', now() - interval '1 hour', 'Africa/Lagos', 'WAT', 30, 'LIVE');
create temporary table ev54b as select id from public.events where slug = 'test-live54b';
insert into public.games (slug, name, platform, scoring_template, status, artwork_url, default_round_count)
values ('test-au54b', 'Test Among Us 54b', 'INSTALL', 'ROLE_OUTCOME', 'ACTIVE', '/games/test-au54b.webp', 1);
insert into event_games (event_id, game_id, position, scoring_template, planned_rounds, scoring_config)
select (select id from ev54b), id, 1, 'ROLE_OUTCOME', 1,
       jsonb_build_object('awards', jsonb_build_object('crewmate', jsonb_build_object('win',1,'loss',0), 'impostor', jsonb_build_object('win',2,'loss',0)))
  from games where slug = 'test-au54b';
create temporary table auGame54b as select id from event_games where event_id = (select id from ev54b) and position = 1;
select pg_temp.register((select id from ev54b), 'lvcoordb', '+2348130000021');
select public.admin_create_room('test-live54b', 'LIVE ROOM B', 8, (select id from event_registrations where alias='lvcoordb'));
create temporary table lvroomb as select id from rooms where event_id=(select id from ev54b) and label='LIVE ROOM B';
select pg_temp.register((select id from ev54b), 'lvb1', '+2348130000022');
select pg_temp.register((select id from ev54b), 'lvb2', '+2348130000023');
select public.transition_event((select id from ev54b), 'CHECK_IN');
select pg_temp.as_player_session((select id from event_registrations where alias='lvb1'));
select public.check_in_player();
select pg_temp.as_player_session((select id from event_registrations where alias='lvb2'));
select public.check_in_player();
select pg_temp.as_staff(gen_random_uuid(), 'SUPER_ADMIN');
select public.transition_event((select id from ev54b), 'LIVE');
select public.start_room_game((select id from lvroomb), (select id from auGame54b));
select public.start_round((select id from lvroomb), (select id from auGame54b));
create temporary table b54round1 as select id from rounds where room_id=(select id from lvroomb) and event_game_id=(select id from auGame54b) and round_index=1;
select public.submit_round_result(
  (select id from b54round1),
  jsonb_build_object('winningRole','crewmate','participants', jsonb_build_array(
    jsonb_build_object('registrationId',(select id from event_registrations where alias='lvb1'),'participation','PARTICIPATING','role','crewmate'),
    jsonb_build_object('registrationId',(select id from event_registrations where alias='lvb2'),'participation','PARTICIPATING','role','impostor')
  )), 'idem-b54r1-0001'
);
select public.request_result_correction(
  (select id from b54round1),
  jsonb_build_object('winningRole','impostor','participants', jsonb_build_array(
    jsonb_build_object('registrationId',(select id from event_registrations where alias='lvb1'),'participation','PARTICIPATING','role','crewmate'),
    jsonb_build_object('registrationId',(select id from event_registrations where alias='lvb2'),'participation','PARTICIPATING','role','impostor')
  )),
  'test correction'
);

select pg_temp.as_player_session((select id from event_registrations where alias='lvb1'));
select is(
  (select (public.get_player_state()->'activeGame'->'lastRoundResult'->>'pending')),
  'true',
  'test 54: a PENDING correction request surfaces as pending=true, nothing more');
select ok(
  not (public.get_player_state()->'activeGame'->'lastRoundResult' ? 'reason')
    and not (public.get_player_state()->'activeGame'->'lastRoundResult' ? 'proposedPayload'),
  'test 54: no correction reason or proposed payload is ever exposed to the player');

select pg_temp.as_staff(gen_random_uuid(), 'SUPER_ADMIN');
select public.admin_approve_correction(
  (select id from correction_requests where round_id = (select id from b54round1) and status='PENDING')
);
select pg_temp.as_player_session((select id from event_registrations where alias='lvb1'));
select is(
  (select (public.get_player_state()->'activeGame'->'lastRoundResult'->>'pending')),
  'false',
  'test 54: pending is false once the correction request is no longer PENDING');

-- ==================================================================== 29. no mutation from read RPCs

create temporary table pre_read_txn_count as select count(*) as n from point_transactions where voided_at is null;
select public.get_player_state();
select public.get_my_game_progress();
select public.get_my_room_standings();
select is(
  (select count(*) from point_transactions where voided_at is null),
  (select n from pre_read_txn_count),
  'test 54: calling every new player-facing read RPC creates or voids zero ledger rows');

select * from finish();
rollback;
