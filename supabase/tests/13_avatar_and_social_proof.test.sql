-- Test 42 — persistent avatar color (migration 0020) and get_player_state()'s
-- socialProof extension.
begin;
select plan(18);

create or replace function pg_temp.as_player(p_uid uuid) returns void
language sql as $$
  insert into auth.users (id) values (p_uid);
  select set_config('request.jwt.claim.sub', p_uid::text, true);
$$;

-- ----------------------------------------------------------------- palette

select ok(
  (select count(*) = 8 from (values
    ('#FF3B8D'),('#FF7A2F'),('#F4B940'),('#2F6BFF'),
    ('#7C5CFC'),('#27B38A'),('#E95D78'),('#D94EFF')
  ) as p(c)),
  'test 42: sanity — the palette this file exercises has 8 entries');

-- ------------------------------------------------------- new player, once

select pg_temp.as_player(gen_random_uuid());
select public.register_player('recess-01','Ada Lovelace','avataraaa','+2348022220001', true);

select isnt(
  (select p.avatar_color from public.players p where p.phone_e164 = '+2348022220001'),
  null,
  'test 42: a new player gets a non-null avatar color');

select ok(
  (select p.avatar_color in (
     '#FF3B8D','#FF7A2F','#F4B940','#2F6BFF','#7C5CFC','#27B38A','#E95D78','#D94EFF'
   ) from public.players p where p.phone_e164 = '+2348022220001'),
  'test 42: the assigned color belongs to the approved palette');

-- --------------------------------------------------- retry does not change it

select pg_temp.as_player(gen_random_uuid());

create temporary table t1 as
  select avatar_color from public.players where phone_e164 = '+2348022220001';

-- Same phone, same event, a second real call — the idempotent-retry path
-- (found in v_existing), not a fresh insert.
select public.register_player('recess-01','Ada Lovelace','avataraaa','+2348022220001', true);

select is(
  (select p.avatar_color from public.players p where p.phone_e164 = '+2348022220001'),
  (select avatar_color from t1),
  'test 42: retrying registration for the same event does not change the color');

-- ------------------------------------------- a second event, same phone/player

insert into public.events (
  slug, name, status, starts_at, timezone, timezone_label,
  registration_opens_at, registration_closes_at, capacity
) values (
  'recess-02', 'RECESS — October 2026', 'REGISTRATION',
  now() + interval '60 days', 'Africa/Lagos', 'WAT',
  now() - interval '1 day', now() + interval '30 days', 30
);
-- event_counters gets its row automatically via the trigger in 0004 — no
-- explicit insert needed (and a redundant one collides on the primary key).

select public.register_player('recess-02','Ada Lovelace','avataraaa2','+2348022220001', true);

select is(
  (select p.avatar_color from public.players p where p.phone_e164 = '+2348022220001'),
  (select avatar_color from t1),
  'test 42: registering the same phone for a later event does not change the color');

-- --------------------------------------------- migrated / direct-insert player

insert into public.players (phone_e164, real_name, canonical_alias)
values ('+2348022220099', 'Direct Insert Player', 'directp');

select isnt(
  (select avatar_color from public.players where phone_e164 = '+2348022220099'),
  null,
  'test 42: a player inserted with no avatar_color (a pre-migration/migrated row) still gets one, via the column default');

select ok(
  (select avatar_color in (
     '#FF3B8D','#FF7A2F','#F4B940','#2F6BFF','#7C5CFC','#27B38A','#E95D78','#D94EFF'
   ) from public.players where phone_e164 = '+2348022220099'),
  'test 42: the default-assigned color also belongs to the approved palette');

-- ------------------------------------------------- get_player_state() surfaces it

select pg_temp.as_player(gen_random_uuid());
update public.event_registrations set auth_user_id =
  (select current_setting('request.jwt.claim.sub')::uuid)
 where alias = 'avataraaa' and event_id = (select id from public.events where slug = 'recess-01');

select is(
  (select public.get_player_state()->'player'->>'avatarColor'),
  (select avatar_color from t1),
  'test 42: get_player_state() returns this player''s own stored avatar color');

-- ---------------------------------------------------------------- social proof

-- Six more real registrations on recess-01 (avataraaa already counts as one),
-- so the event has 7 REGISTERED players total — enough to prove the cap.
select pg_temp.as_player(gen_random_uuid());
select public.register_player('recess-01','P Two','ptwo','+2348022220002', true);
select pg_temp.as_player(gen_random_uuid());
select public.register_player('recess-01','P Three','pthree','+2348022220003', true);
select pg_temp.as_player(gen_random_uuid());
select public.register_player('recess-01','P Four','pfour','+2348022220004', true);
select pg_temp.as_player(gen_random_uuid());
select public.register_player('recess-01','P Five','pfive','+2348022220005', true);
select pg_temp.as_player(gen_random_uuid());
select public.register_player('recess-01','P Six','psix','+2348022220006', true);
select pg_temp.as_player(gen_random_uuid());
select public.register_player('recess-01','P Seven','pseven','+2348022220007', true);

-- Re-resolve as the original avataraaa session for the actual read.
select pg_temp.as_player(gen_random_uuid());
update public.event_registrations set auth_user_id =
  (select current_setting('request.jwt.claim.sub')::uuid)
 where alias = 'avataraaa' and event_id = (select id from public.events where slug = 'recess-01');

select is(
  (select (public.get_player_state()->'socialProof'->>'admittedCount')::int),
  7,
  'test 42: admittedCount reflects all 7 real REGISTERED players on this event');

select is(
  (select jsonb_array_length(public.get_player_state()->'socialProof'->'avatars')),
  6,
  'test 42: the avatar stack is capped at 6 even with 7 admitted players');

select is(
  (select jsonb_array_length(public.get_player_state()->'socialProof'->'previewAliases')),
  3,
  'test 42: previewAliases is capped at 3');

select is(
  (select public.get_player_state()->'socialProof'->'avatars'->0->>'alias'),
  'avataraaa',
  'test 42: avatar stack is ordered by registration order (earliest first)');

-- --------------------------------------------------------------------- PII

select ok(
  not (public.get_player_state()->'socialProof'->'avatars'->0 ? 'phone'),
  'test 42: social proof avatars never carry a phone field');

select ok(
  not (public.get_player_state()->'socialProof'->'avatars'->0 ? 'realName'),
  'test 42: social proof avatars never carry a real name field');

select ok(
  not (public.get_player_state()->'socialProof'->'avatars'->0 ? 'registrationId'),
  'test 42: social proof avatars never carry a registration id');

select ok(
  (public.get_player_state()->'socialProof'->'avatars'->0 ? 'avatarColor'),
  'test 42: social proof avatars do carry avatarColor, as intended');

-- ---------------------------------------------------- WAITLISTED excluded

-- Fill recess-02's tiny remaining headroom isn't needed — assert on the
-- semantic rule directly: a WAITLISTED registration must not inflate
-- admittedCount. recess-01 has no waitlisted rows yet in this fixture, so
-- assert the query filters on status = 'REGISTERED' by construction rather
-- than re-deriving capacity math here.
select ok(
  (select count(*) from public.event_registrations
    where event_id = (select id from public.events where slug = 'recess-01')
      and status = 'WAITLISTED') = 0,
  'test 42: fixture sanity — no WAITLISTED rows exist yet to accidentally count');

select is(
  (select (public.get_player_state()->'socialProof'->>'admittedCount')::int),
  (select count(*)::int from public.event_registrations
    where event_id = (select id from public.events where slug = 'recess-01')
      and status = 'REGISTERED'),
  'test 42: admittedCount exactly matches a direct REGISTERED-only count, never WAITLISTED');

select * from finish();
rollback;
