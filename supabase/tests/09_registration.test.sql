-- Test 38 — register_player() and get_my_registration(), migration 0016.
begin;
select plan(28);

create temporary table t as select id, capacity from public.events where slug = 'recess-01';

-- helper: pretend to be a freshly anonymous-signed-in player. A real
-- signInAnonymously() always creates the auth.users row first — audit_logs
-- and event_registrations both key off it — so the fixture does too, rather
-- than only forging the JWT claim.
create or replace function pg_temp.as_player(p_uid uuid) returns void
language sql as $$
  insert into auth.users (id) values (p_uid);
  select set_config('request.jwt.claim.sub', p_uid::text, true);
$$;

-- ----------------------------------------------------------------- rejections

select throws_like(
  $$ select public.register_player('recess-01','Ada Lovelace','ADA','+2348011111111', true) $$,
  'not_authenticated:%',
  'test 38: refuses to run with no session at all');

select pg_temp.as_player(gen_random_uuid());

select throws_like(
  $$ select public.register_player('recess-01','','ADA','+2348011111111', true) $$,
  'invalid_name:%', 'test 38: refuses a blank name');

select throws_like(
  $$ select public.register_player('recess-01','Ada Lovelace','A','+2348011111111', true) $$,
  'invalid_alias:%', 'test 38: refuses a one-character alias');

select throws_like(
  $$ select public.register_player('recess-01','Ada Lovelace','ADA LOVELACE','+2348011111111', true) $$,
  'invalid_alias:%', 'test 38: refuses a space in the alias');

select throws_like(
  $$ select public.register_player('recess-01','Ada Lovelace','ADA','08011111111', true) $$,
  'invalid_phone:%', 'test 38: refuses a phone with no +country code');

select throws_like(
  $$ select public.register_player('recess-01','Ada Lovelace','ADA','+2348011111111', false) $$,
  'consent_required:%', 'test 38: refuses submission without consent');

select throws_like(
  $$ select public.register_player('does-not-exist','Ada Lovelace','ADA','+2348011111111', true) $$,
  'event_not_found:%', 'test 38: refuses an unknown event slug');

-- ------------------------------------------------------------------- success

select pg_temp.as_player(gen_random_uuid());
select lives_ok(
  $$ select public.register_player('recess-01','Ada Lovelace','ADA','+2348011111111', true) $$,
  'test 38: a valid registration succeeds');

select is(
  (select alias from public.event_registrations where event_id = (select id from t) and lower(alias) = 'ada'),
  'ADA', 'test 38: the alias is stored as typed');

select is(
  (select status from public.event_registrations where event_id = (select id from t) and lower(alias) = 'ada'),
  'REGISTERED'::public.registration_status, 'test 38: a registration under capacity is REGISTERED');

select is(
  (select player_number from public.event_registrations where event_id = (select id from t) and lower(alias) = 'ada'),
  1, 'test 38: the first registration for this event gets player_number 1');

select is(
  (select real_name from public.players where phone_e164 = '+2348011111111'),
  'Ada Lovelace', 'test 38: the player identity is created from the phone number');

select is(
  (select marketing_consent from public.players where phone_e164 = '+2348011111111'),
  true, 'test 38: consent is recorded on the player');

select is(
  (select auth_user_id from public.event_registrations where event_id = (select id from t) and lower(alias) = 'ada'),
  (select current_setting('request.jwt.claim.sub')::uuid),
  'test 38: the registration is linked to the calling anonymous session');

-- ------------------------------------------------------------- idempotent retry

select is(
  (select count(*)::int from public.event_registrations where event_id = (select id from t) and player_id =
    (select id from public.players where phone_e164 = '+2348011111111')),
  1, 'test 38: exactly one registration exists before the retry');

select lives_ok(
  $$ select public.register_player('recess-01','Ada Lovelace','ADA','+2348011111111', true) $$,
  'test 38: retrying the same session/phone does not raise');

select is(
  (select count(*)::int from public.event_registrations where event_id = (select id from t) and player_id =
    (select id from public.players where phone_e164 = '+2348011111111')),
  1, 'test 38: the retry did not create a second registration');

select is(
  (select count(*)::int from public.players where phone_e164 = '+2348011111111'),
  1, 'test 38: the retry did not create a second player');

-- --------------------------------------------------------------- alias collision

select pg_temp.as_player(gen_random_uuid());
select throws_like(
  $$ select public.register_player('recess-01','Somebody Else','ada','+2348011111112', true) $$,
  'alias_taken:%', 'test 38: a case-insensitive alias collision is refused');

-- a failed alias collision must not have consumed a player_number
select pg_temp.as_player(gen_random_uuid());
select lives_ok(
  $$ select public.register_player('recess-01','Bola Balogun','BOLA','+2348011111113', true) $$,
  'test 38: the next real registration succeeds after a rejected collision');
select is(
  (select player_number from public.event_registrations where event_id=(select id from t) and lower(alias)='bola'),
  2, 'test 38: the rejected alias collision left no gap in player_number');

-- ------------------------------------------------------------------- get_my_registration

select is(
  (select alias from public.get_my_registration()),
  'BOLA', 'test 38: get_my_registration returns the caller''s own registration');

select pg_temp.as_player(gen_random_uuid());
select is(
  (select count(*)::int from public.get_my_registration()),
  0, 'test 38: get_my_registration returns nothing for a session with no registration');

-- --------------------------------------------------------------------- capacity

update public.events set capacity = 3 where id = (select id from t);
select pg_temp.as_player(gen_random_uuid());
select lives_ok(
  $$ select public.register_player('recess-01','Chidi Okafor','CHIDI','+2348011111114', true) $$,
  'test 38: registration at exactly capacity still succeeds (fills the last seat)');
select is(
  (select status from public.event_registrations where event_id=(select id from t) and lower(alias)='chidi'),
  'REGISTERED'::public.registration_status, 'test 38: the registration that fills capacity is REGISTERED');

select pg_temp.as_player(gen_random_uuid());
select lives_ok(
  $$ select public.register_player('recess-01','Femi Adeyemi','FEMI','+2348011111115', true) $$,
  'test 38: registration past capacity is written, not refused');
select is(
  (select status from public.event_registrations where event_id=(select id from t) and lower(alias)='femi'),
  'WAITLISTED'::public.registration_status, 'test 38: a registration past capacity is WAITLISTED, not REGISTERED');
select isnt(
  (select player_number from public.event_registrations where event_id=(select id from t) and lower(alias)='femi'),
  null, 'test 38: a waitlisted registration still receives a player_number');

select * from finish();
rollback;
