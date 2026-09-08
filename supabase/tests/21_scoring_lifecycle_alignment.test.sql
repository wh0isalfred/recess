-- Test 50 — Phase 7.2: scoring lifecycle alignment (migration 0028).
begin;
select plan(28);

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
values ('test-life28', 'Lifecycle Event', 'LIVE', now() - interval '1 hour', 'Africa/Lagos', 'WAT', 30);
create temporary table ev28 as select id from public.events where slug = 'test-life28';

insert into public.games (slug, name, platform, scoring_template, status, artwork_url, default_round_count)
values ('test-au28', 'Test Among Us 28', 'INSTALL', 'ROLE_OUTCOME', 'ACTIVE', '/games/test-au28.webp', 3);
insert into event_games (event_id, game_id, position, scoring_template, planned_rounds, scoring_config)
select (select id from ev28), id, 1, 'ROLE_OUTCOME', 3,
       jsonb_build_object('awards', jsonb_build_object(
         'crewmate', jsonb_build_object('win', 1, 'loss', 0),
         'impostor', jsonb_build_object('win', 2, 'loss', 0)
       ))
  from games where slug = 'test-au28';
create temporary table auGame28 as select id from event_games where event_id = (select id from ev28) and position = 1;

select pg_temp.register((select id from ev28), 'lcoord1', '+2348090000001');
select public.admin_create_room('test-life28', 'LIFE ROOM 01', 8,
  (select id from public.event_registrations where alias = 'lcoord1'));
create temporary table lroom1 as select id from rooms where event_id = (select id from ev28) and label = 'LIFE ROOM 01';

select pg_temp.register((select id from ev28), 'lcoord2', '+2348090000002');
select public.admin_create_room('test-life28', 'LIFE ROOM 02', 8,
  (select id from public.event_registrations where alias = 'lcoord2'));
create temporary table lroom2 as select id from rooms where event_id = (select id from ev28) and label = 'LIFE ROOM 02';

select pg_temp.register((select id from ev28), 'l1', '+2348090000011');
select pg_temp.register((select id from ev28), 'l2', '+2348090000012');
insert into room_memberships (event_id, room_id, registration_id)
select (select id from ev28), (select id from lroom1), id from event_registrations where alias in ('l1','l2');

select public.start_room_game((select id from lroom1), (select id from auGame28));

-- ==================================================================== 1. INITIAL CONFIRMATION

select lives_ok(
  $$ select public.start_round((select id from lroom1), (select id from auGame28)) $$,
  'test 50: round 1 starts fine');
create temporary table lround1 as select id from rounds where room_id=(select id from lroom1) and event_game_id=(select id from auGame28) and round_index=1;
select lives_ok(
  $$ select public.submit_round_result(
       (select id from lround1),
       jsonb_build_object('winningRole','impostor','participants', jsonb_build_array(
         jsonb_build_object('registrationId',(select id from event_registrations where alias='l1'),'participation','PARTICIPATING','role','impostor'),
         jsonb_build_object('registrationId',(select id from event_registrations where alias='l2'),'participation','PARTICIPATING','role','crewmate')
       )), 'idem-lround1-0001'
     ) $$,
  'test 50: coordinator''s initial confirmation of a round succeeds');

-- ==================================================================== 2. DIRECT CORRECTION REJECTED

select throws_like(
  $$ select public.submit_round_result(
       (select id from lround1),
       jsonb_build_object('winningRole','crewmate','participants', jsonb_build_array(
         jsonb_build_object('registrationId',(select id from event_registrations where alias='l1'),'participation','PARTICIPATING','role','crewmate'),
         jsonb_build_object('registrationId',(select id from event_registrations where alias='l2'),'participation','PARTICIPATING','role','crewmate')
       )), 'idem-lround1-ATTEMPTED-CORRECTION'
     ) $$,
  'correction_requires_request%',
  'test 50: a direct correction attempt on an already-confirmed round is rejected, coordinator or not');

select is(
  (select public.submit_round_result((select id from lround1), '{}'::jsonb, 'idem-lround1-0001')->>'idempotent'),
  'true',
  'test 50: a genuine retry with the original idempotency key still succeeds as idempotent, not blocked by the correction restriction');

-- ==================================================================== 3. REASON REQUIRED

select throws_like(
  $$ select public.request_result_correction(
       (select id from lround1),
       jsonb_build_object('winningRole','crewmate','participants', jsonb_build_array(
         jsonb_build_object('registrationId',(select id from event_registrations where alias='l1'),'participation','PARTICIPATING','role','crewmate'),
         jsonb_build_object('registrationId',(select id from event_registrations where alias='l2'),'participation','PARTICIPATING','role','crewmate')
       )),
       ''
     ) $$,
  'invalid_reason%',
  'test 50: a correction request with an empty reason is rejected');

-- ==================================================================== 4. INVALID PAYLOAD REJECTED

select throws_like(
  $$ select public.request_result_correction(
       (select id from lround1),
       jsonb_build_object('winningRole','crewmate','participants', jsonb_build_array(
         jsonb_build_object('registrationId', gen_random_uuid(), 'participation','PARTICIPATING','role','crewmate')
       )),
       'real reason but bad payload'
     ) $$,
  'invalid_participant%',
  'test 50: a correction request with an invalid proposed payload is rejected by the same validator normal submission uses');

-- ==================================================================== 5. CROSS-ROOM REJECTED

select pg_temp.as_player_session((select id from event_registrations where alias = 'lcoord2'));
select throws_ok(
  $$ select public.request_result_correction(
       (select id from lround1),
       jsonb_build_object('winningRole','crewmate','participants', jsonb_build_array(
         jsonb_build_object('registrationId',(select id from event_registrations where alias='l1'),'participation','PARTICIPATING','role','crewmate'),
         jsonb_build_object('registrationId',(select id from event_registrations where alias='l2'),'participation','PARTICIPATING','role','crewmate')
       )),
       'room 2''s coordinator should not be able to touch room 1''s round'
     ) $$,
  '42501', null,
  'test 50: room 2''s coordinator cannot request a correction for room 1''s round');

-- ==================================================================== 6. VALID REQUEST, NO SCORING MUTATION

select pg_temp.as_staff(gen_random_uuid(), 'SUPER_ADMIN');
create temporary table pre_request_result as
  select id, payload from results where round_id = (select id from lround1) and superseded_at is null;
create temporary table pre_request_txn_count as
  select count(*) as n from point_transactions where registration_id in (select id from event_registrations where alias in ('l1','l2')) and voided_at is null;

select lives_ok(
  $$ select public.request_result_correction(
       (select id from lround1),
       jsonb_build_object('winningRole','crewmate','participants', jsonb_build_array(
         jsonb_build_object('registrationId',(select id from event_registrations where alias='l1'),'participation','PARTICIPATING','role','crewmate'),
         jsonb_build_object('registrationId',(select id from event_registrations where alias='l2'),'participation','PARTICIPATING','role','crewmate')
       )),
       'l1 was actually crewmate, not impostor'
     ) $$,
  'test 50: a valid, well-formed correction request from an authorized actor succeeds');
create temporary table req1 as select id from correction_requests where round_id = (select id from lround1) and status = 'PENDING';

select is(
  (select id from results where round_id = (select id from lround1) and superseded_at is null),
  (select id from pre_request_result),
  'test 50: the authoritative result is completely unchanged by a pending request');
select is(
  (select count(*) from point_transactions where registration_id in (select id from event_registrations where alias in ('l1','l2')) and voided_at is null),
  (select n from pre_request_txn_count),
  'test 50: no ledger mutation occurred from creating a pending request (round-1-only game, not yet settled — count stays exactly what it was)');

-- ==================================================================== 7+8. ADMIN REJECT

select lives_ok(
  $$ select public.admin_reject_correction((select id from req1), 'not needed, original call stands') $$,
  'test 50: Admin can reject a pending correction request');
select is(
  (select status::text from correction_requests where id = (select id from req1)),
  'REJECTED',
  'test 50: the request status is REJECTED');
select is(
  (select id from results where round_id = (select id from lround1) and superseded_at is null),
  (select id from pre_request_result),
  'test 50: rejection changed no scoring state — the authoritative result is still the original');

-- ==================================================================== 9+10+11. ADMIN APPROVE

select lives_ok(
  $$ select public.request_result_correction(
       (select id from lround1),
       jsonb_build_object('winningRole','crewmate','participants', jsonb_build_array(
         jsonb_build_object('registrationId',(select id from event_registrations where alias='l1'),'participation','PARTICIPATING','role','crewmate'),
         jsonb_build_object('registrationId',(select id from event_registrations where alias='l2'),'participation','PARTICIPATING','role','crewmate')
       )),
       'l1 was actually crewmate, not impostor'
     ) $$,
  'test 50: a fresh correction request can be created after the prior one was rejected (no lingering pending-request conflict)');
create temporary table req2 as select id from correction_requests where round_id = (select id from lround1) and status = 'PENDING';

select lives_ok(
  $$ select public.admin_approve_correction((select id from req2)) $$,
  'test 50: Admin can approve a pending correction request');
select isnt(
  (select id from results where round_id = (select id from lround1) and superseded_at is null),
  (select id from pre_request_result),
  'test 50: approval supersedes the old result with a genuinely new authoritative one');
select is(
  (select status::text from correction_requests where id = (select id from req2)),
  'APPROVED',
  'test 50: the request status is APPROVED');

-- ==================================================================== 12. STANDINGS REFLECT CORRECTION

select is(
  (select (jsonb_path_query_first(public.room_standings((select id from lroom1)), '$[*] ? (@.alias == "l1")')->>'totalPoints')::int),
  0,
  'test 50: after correction (l1 now crewmate+crewmate win = 0 raw, tied last), standings reflect the corrected reality, not the original');

-- ==================================================================== 13. DOUBLE APPROVAL IDEMPOTENT

create temporary table post_approve_result as
  select id from results where round_id = (select id from lround1) and superseded_at is null;
select is(
  (select public.admin_approve_correction((select id from req2))->>'idempotent'),
  'true',
  'test 50: approving the same request a second time is a safe idempotent no-op');
select is(
  (select id from results where round_id = (select id from lround1) and superseded_at is null),
  (select id from post_approve_result),
  'test 50: the double approval created no additional result row — the authoritative result is unchanged');

-- ==================================================================== 14. STALE REQUEST

select lives_ok(
  $$ select public.request_result_correction(
       (select id from lround1),
       jsonb_build_object('winningRole','impostor','participants', jsonb_build_array(
         jsonb_build_object('registrationId',(select id from event_registrations where alias='l1'),'participation','PARTICIPATING','role','impostor'),
         jsonb_build_object('registrationId',(select id from event_registrations where alias='l2'),'participation','PARTICIPATING','role','crewmate')
       )),
       'staleness test: this request will go stale before approval'
     ) $$,
  'test 50: a new correction request against the current result is created');
create temporary table req3 as select id from correction_requests where round_id = (select id from lround1) and status = 'PENDING';

select public.admin_direct_correction(
  (select id from lround1),
  jsonb_build_object('winningRole','crewmate','participants', jsonb_build_array(
    jsonb_build_object('registrationId',(select id from event_registrations where alias='l1'),'participation','DNP'),
    jsonb_build_object('registrationId',(select id from event_registrations where alias='l2'),'participation','PARTICIPATING','role','crewmate')
  )),
  'direct fix while req3 is still pending'
);

select throws_like(
  $$ select public.admin_approve_correction((select id from req3)) $$,
  'stale_correction_request%',
  'test 50: approving a request whose target result has since changed is refused, not blindly applied');

-- ==================================================================== 15. DIRECT ADMIN CORRECTION REASON

select throws_like(
  $$ select public.admin_direct_correction(
       (select id from lround1),
       jsonb_build_object('winningRole','crewmate','participants', jsonb_build_array(
         jsonb_build_object('registrationId',(select id from event_registrations where alias='l1'),'participation','DNP'),
         jsonb_build_object('registrationId',(select id from event_registrations where alias='l2'),'participation','PARTICIPATING','role','crewmate')
       )),
       ''
     ) $$,
  'invalid_reason%',
  'test 50: a direct Admin correction with no reason is rejected');

-- ==================================================================== 16-20. COMPLETION GATING

select pg_temp.register((select id from ev28), 'g1', '+2348090000021');
select pg_temp.register((select id from ev28), 'g2', '+2348090000022');
insert into room_memberships (event_id, room_id, registration_id)
select (select id from ev28), (select id from lroom2), id from event_registrations where alias in ('g1','g2');

insert into public.games (slug, name, platform, scoring_template, status, artwork_url, default_round_count)
values ('test-au28b', 'Test Among Us 28b', 'INSTALL', 'ROLE_OUTCOME', 'ACTIVE', '/games/test-au28b.webp', 3);
insert into event_games (event_id, game_id, position, scoring_template, planned_rounds, duration_minutes, scoring_config)
select (select id from ev28), id, 1, 'ROLE_OUTCOME', 3, 30,
       jsonb_build_object('awards', jsonb_build_object(
         'crewmate', jsonb_build_object('win', 1, 'loss', 0),
         'impostor', jsonb_build_object('win', 2, 'loss', 0)
       ))
  from games where slug = 'test-au28b'
  on conflict (event_id, game_id) do nothing;
create temporary table au28bGame as select id from event_games where event_id = (select id from ev28) and game_id = (select id from games where slug='test-au28b');

select public.start_room_game((select id from lroom2), (select id from au28bGame));
select public.start_round((select id from lroom2), (select id from au28bGame));
create temporary table g1round1 as select id from rounds where room_id=(select id from lroom2) and event_game_id=(select id from au28bGame) and round_index=1;
select public.submit_round_result(
  (select id from g1round1),
  jsonb_build_object('winningRole','crewmate','participants', jsonb_build_array(
    jsonb_build_object('registrationId',(select id from event_registrations where alias='g1'),'participation','PARTICIPATING','role','crewmate'),
    jsonb_build_object('registrationId',(select id from event_registrations where alias='g2'),'participation','PARTICIPATING','role','crewmate')
  )), 'idem-g1round1-0001'
);

select throws_like(
  $$ select public.complete_room_game((select id from lroom2), (select id from au28bGame)) $$,
  'room_game_not_ready%',
  'test 50: a coordinator cannot complete a 3-round game after only 1 completed round while the window is still open');

select public.start_round((select id from lroom2), (select id from au28bGame));
create temporary table g1round2 as select id from rounds where room_id=(select id from lroom2) and event_game_id=(select id from au28bGame) and round_index=2;
select public.void_round((select id from g1round2), 'test fixture: simulate a crash');
select throws_like(
  $$ select public.complete_room_game((select id from lroom2), (select id from au28bGame)) $$,
  'room_game_not_ready%',
  'test 50: a voided round does not count toward the completed-round maximum — still only 1 of 3 real completions');

select public.start_round((select id from lroom2), (select id from au28bGame));
create temporary table g1round2b as select id from rounds where room_id=(select id from lroom2) and event_game_id=(select id from au28bGame) and round_index=3;
select public.submit_round_result(
  (select id from g1round2b),
  jsonb_build_object('winningRole','crewmate','participants', jsonb_build_array(
    jsonb_build_object('registrationId',(select id from event_registrations where alias='g1'),'participation','PARTICIPATING','role','crewmate'),
    jsonb_build_object('registrationId',(select id from event_registrations where alias='g2'),'participation','PARTICIPATING','role','crewmate')
  )), 'idem-g1round2b-0001'
);
select public.start_round((select id from lroom2), (select id from au28bGame));
create temporary table g1round3 as select id from rounds where room_id=(select id from lroom2) and event_game_id=(select id from au28bGame) and round_index=4;
select public.submit_round_result(
  (select id from g1round3),
  jsonb_build_object('winningRole','crewmate','participants', jsonb_build_array(
    jsonb_build_object('registrationId',(select id from event_registrations where alias='g1'),'participation','PARTICIPATING','role','crewmate'),
    jsonb_build_object('registrationId',(select id from event_registrations where alias='g2'),'participation','PARTICIPATING','role','crewmate')
  )), 'idem-g1round3-0001'
);
select lives_ok(
  $$ select public.complete_room_game((select id from lroom2), (select id from au28bGame)) $$,
  'test 50: a coordinator can complete after 3 genuinely valid completed rounds are reached');

-- Time-expiry path, on a fresh event_game/room pairing.
insert into public.games (slug, name, platform, scoring_template, status, artwork_url, default_round_count)
values ('test-tv28', 'Test Trivia 28', 'BROWSER', 'PLACEMENT', 'ACTIVE', '/games/test-tv28.webp', 5)
on conflict (slug) do nothing;
insert into event_games (event_id, game_id, position, scoring_template, planned_rounds, duration_minutes, scoring_config)
select (select id from ev28), id, 2, 'PLACEMENT', 5, 30, jsonb_build_object('type','placement')
  from games where slug = 'test-tv28'
  on conflict (event_id, game_id) do nothing;
create temporary table tv28Game as select id from event_games where event_id = (select id from ev28) and position = 2;

select public.start_room_game((select id from lroom2), (select id from tv28Game));
select public.start_round((select id from lroom2), (select id from tv28Game));
create temporary table tv28round1 as select id from rounds where room_id=(select id from lroom2) and event_game_id=(select id from tv28Game) and round_index=1;

update room_event_games set started_at = now() - interval '999 hours'
 where room_id = (select id from lroom2) and event_game_id = (select id from tv28Game);
select throws_like(
  $$ select public.complete_room_game((select id from lroom2), (select id from tv28Game)) $$,
  'round_still_live%',
  'test 50: completion remains blocked while a round is LIVE, even with an expired window');

select public.submit_round_result(
  (select id from tv28round1),
  jsonb_build_object('scores', jsonb_build_array(
    jsonb_build_object('registrationId',(select id from event_registrations where alias='g1'),'participation','PARTICIPATING','rawScore',10),
    jsonb_build_object('registrationId',(select id from event_registrations where alias='g2'),'participation','PARTICIPATING','rawScore',20)
  )), 'idem-tv28round1-0001'
);
select lives_ok(
  $$ select public.complete_room_game((select id from lroom2), (select id from tv28Game)) $$,
  'test 50: a coordinator can complete after the configured time window has expired, once no round remains LIVE, even short of the planned round count');

select * from finish();
rollback;
