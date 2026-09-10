-- Test 52 — Phase 8.1: Player Access & Secure Multi-Device Recovery (migration 0030).
begin;
select plan(19);

create or replace function pg_temp.as_player(p_uid uuid) returns void
language sql as $$
  insert into auth.users (id) values (p_uid);
  select set_config('request.jwt.claim.sub', p_uid::text, true);
$$;

-- Simulates a real Supabase phone-OTP-verified session: a fresh auth.users
-- row with phone/phone_confirmed_at actually set — exactly the server-side
-- state recover_player_access() reads, never a client-supplied phone.
create or replace function pg_temp.as_verified_phone_session(p_uid uuid, p_phone_e164 text) returns void
language plpgsql as $$
declare v_digits text := regexp_replace(p_phone_e164, '^\+', '');
begin
  insert into auth.users (id, phone, phone_confirmed_at) values (p_uid, v_digits, now());
  perform set_config('request.jwt.claim.sub', p_uid::text, true);
end $$;

insert into public.events (
  slug, name, status, starts_at, timezone, timezone_label,
  registration_opens_at, registration_closes_at, capacity
) values (
  'test-access52', 'Access Recovery Event', 'REGISTRATION',
  now() + interval '10 days', 'Africa/Lagos', 'WAT',
  now() - interval '1 day', now() + interval '30 days', 30
);

-- ==================================================================== ANONYMOUS FIRST-TIME REGISTRATION

select pg_temp.as_player(gen_random_uuid());
select lives_ok(
  $$ select public.register_player('test-access52','Kemi Original','kemi','+2348110000001', true) $$,
  'test 52: anonymous first-time registration with a brand-new phone still succeeds');
select isnt(
  (select public.current_player_id()),
  null,
  'test 52: the registering session is immediately recognized as the new player');

-- ==================================================================== EXISTING-PHONE TAKEOVER BLOCKED

select pg_temp.as_player(gen_random_uuid());
select throws_like(
  $$ select public.register_player('test-access52','Attacker Name','attacker','+2348110000001', true) $$,
  'phone_already_registered%',
  'test 52: a fresh, unrecognized session submitting someone else''s real phone is refused, not silently taken over');

select is(
  (select real_name from public.players where phone_e164 = '+2348110000001'),
  'Kemi Original',
  'test 52: the existing player''s real_name was NOT modified by the blocked attempt');
select is(
  (select count(*) from event_registrations er join players p on p.id = er.player_id
    where p.phone_e164 = '+2348110000001'),
  1::bigint,
  'test 52: no second registration was created for that player by the blocked attempt');

-- The same blocked session can still register legitimately with a
-- genuinely unclaimed phone — the refusal above was correctly scoped to
-- the specific conflicting phone, not a blanket ban on that session.
select lives_ok(
  $$ select public.register_player('test-access52','Genuinely New Person','newperson','+2348110000099', true) $$,
  'test 52: the same session, given a genuinely unclaimed phone, registers normally — the earlier block was scoped to the conflicting phone only'
);

-- ==================================================================== UNVERIFIED USER CANNOT CLAIM / DIRECT RPC BYPASS

select pg_temp.as_player(gen_random_uuid());
select throws_like(
  $$ select public.recover_player_access() $$,
  'phone_not_verified%',
  'test 52: a session with no verified phone at all cannot recover any player''s access');

-- ==================================================================== VERIFIED WRONG PHONE CANNOT RECOVER ANOTHER PLAYER

select pg_temp.as_verified_phone_session(gen_random_uuid(), '+2348110000002');
select throws_like(
  $$ select public.recover_player_access() $$,
  'player_not_found%',
  'test 52: a genuinely verified phone that matches no player is refused, not silently linked to someone else''s player');

-- ==================================================================== VERIFIED MATCHING PHONE CAN RECOVER

select pg_temp.as_verified_phone_session(gen_random_uuid(), '+2348110000001');
select lives_ok(
  $$ select public.recover_player_access() $$,
  'test 52: a genuinely verified session whose phone matches an existing player can recover access');
select is(
  (select (public.recover_player_access())->>'recovered'),
  'true',
  'test 52: the recovery call reports success');

-- ==================================================================== RECOVERY IS IDEMPOTENT

select is(
  (select count(*) from player_auth_identities
    where auth_user_id = (select current_setting('request.jwt.claim.sub')::uuid)),
  1::bigint,
  'test 52: repeating recovery for the same already-recognized session creates no duplicate identity row');

-- ==================================================================== MULTIPLE AUTHORIZED DEVICES + OLD DEVICE STILL WORKS

create temporary table original_device_uid as select (select auth_user_id from event_registrations where alias = 'kemi') as uid;
create temporary table recovered_device_uid as select current_setting('request.jwt.claim.sub')::uuid as uid;

-- Original device: still a completely valid session for the same player.
select set_config('request.jwt.claim.sub', (select uid::text from original_device_uid), true);
select is(
  (select public.current_player_id()),
  (select player_id from event_registrations where alias = 'kemi'),
  'test 52: the ORIGINAL device''s session still resolves to the correct player after recovery on a new device');

-- Recovered device: also still valid.
select set_config('request.jwt.claim.sub', (select uid::text from recovered_device_uid), true);
select is(
  (select public.current_player_id()),
  (select player_id from event_registrations where alias = 'kemi'),
  'test 52: the NEWLY RECOVERED device''s session resolves to the same correct player');

select is(
  (select count(*) from player_auth_identities where player_id = (select player_id from event_registrations where alias = 'kemi')),
  2::bigint,
  'test 52: two distinct authorized device identities now exist for this one player — neither replaced the other');

-- ==================================================================== ANONYMOUS RE-REGISTRATION STILL RESOLVES CORRECTLY (recovered session)

select lives_ok(
  $$ select public.register_player('test-access52','Kemi Original','kemi','+2348110000001', true) $$,
  'test 52: the recovered device can also legitimately re-submit registration for the same player (idempotent path, not a new one)');

-- ==================================================================== COORDINATOR AUTHORIZATION STILL WORKS AFTER RECOVERY

create or replace function pg_temp.as_staff(p_uid uuid, p_role public.staff_role) returns void
language sql as $$
  insert into auth.users (id) values (p_uid);
  insert into public.staff_profiles (user_id, name, role) values (p_uid, 'Test Staff', p_role);
  select set_config('request.jwt.claim.sub', p_uid::text, true);
$$;

select pg_temp.as_staff(gen_random_uuid(), 'SUPER_ADMIN');
select public.admin_create_room('test-access52', 'ACCESS ROOM 01', 8,
  (select id from event_registrations where alias = 'kemi'));
create temporary table aroom as select id from rooms where event_id = (select id from events where slug='test-access52') and label = 'ACCESS ROOM 01';

-- Kemi's ORIGINAL device, as the room's coordinator.
select set_config('request.jwt.claim.sub', (select uid::text from original_device_uid), true);
select ok(
  public.is_authorized_for_room((select id from aroom)),
  'test 52: the original device is still recognized as this room''s coordinator after recovery happened on another device');

-- Kemi's RECOVERED device, same coordinator authority.
select set_config('request.jwt.claim.sub', (select uid::text from recovered_device_uid), true);
select ok(
  public.is_authorized_for_room((select id from aroom)),
  'test 52: the newly recovered device is ALSO recognized as this room''s coordinator — either device can coordinate');

-- An unrelated verified-but-unassociated session is still refused.
select pg_temp.as_verified_phone_session(gen_random_uuid(), '+2348110000077');
select ok(
  not public.is_authorized_for_room((select id from aroom)),
  'test 52: an unrelated session (verified phone, no relation to this room) is still correctly refused coordinator authority');

-- ==================================================================== DIRECT RPC BYPASS

select pg_temp.as_player(gen_random_uuid());
select throws_like(
  $$ select public.recover_player_access() $$,
  'phone_not_verified%',
  'test 52: calling recover_player_access() directly with no verified phone at all fails the same way regardless of UI');

select * from finish();
rollback;
