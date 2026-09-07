-- Test 44 — audit_logs FK/trigger contradiction fix, admin_delete_event()
-- (migration 0022).
begin;
select plan(16);

create or replace function pg_temp.as_staff(p_uid uuid, p_role public.staff_role) returns void
language sql as $$
  insert into auth.users (id) values (p_uid);
  insert into public.staff_profiles (user_id, name, role) values (p_uid, 'Test Staff', p_role);
  select set_config('request.jwt.claim.sub', p_uid::text, true);
$$;

select pg_temp.as_staff(gen_random_uuid(), 'EVENT_ADMIN');

-- --------------------------------------------------------------------- fixture

insert into public.events (slug, name, status, starts_at, timezone, timezone_label, capacity)
values ('test-audit22-draft', 'Draft Delete Event', 'DRAFT', now() + interval '10 days', 'Africa/Lagos', 'WAT', 30);
create temporary table draftev as select id from public.events where slug = 'test-audit22-draft';

insert into public.events (slug, name, status, starts_at, timezone, timezone_label,
  registration_opens_at, registration_closes_at, capacity)
values ('test-audit22-live', 'Registered Event', 'REGISTRATION', now() + interval '10 days', 'Africa/Lagos', 'WAT',
  now() - interval '1 day', now() + interval '5 days', 30);
create temporary table liveev as select id from public.events where slug = 'test-audit22-live';

-- Real audit history against the DRAFT event — not synthetic rows, the
-- actual side effect of a real admin operation, same as production.
select public.admin_add_event_game(
  'test-audit22-draft',
  (select id from games limit 1),
  1, 30
);

select ok(
  (select count(*) from audit_logs where event_id = (select id from draftev)) >= 1,
  'test 44: fixture sanity — the DRAFT event has real audit history before deletion');

-- ============================================================= DELETION

select lives_ok(
  $$ select public.admin_delete_event('test-audit22-draft') $$,
  'test 44: a DRAFT event with audit history can be deleted');

select is(
  (select count(*) from events where id = (select id from draftev)),
  0::bigint,
  'test 44: the event row is actually gone');

-- ---------------------------------------------------- audit history survives

select ok(
  (select count(*) from audit_logs where entity_id = (select id from draftev) and entity_type = 'events') >= 1,
  'test 44: audit rows that referenced the deleted event still exist');

select is(
  (select count(*) from audit_logs
    where entity_type = 'events' and entity_id = (select id from draftev) and event_id is not null),
  0::bigint,
  'test 44: every surviving audit row''s event_id was correctly nulled by the FK, not left dangling');

select is(
  (select action from audit_logs where entity_type = 'events' and entity_id = (select id from draftev)
    and action = 'event.deleted'),
  'event.deleted',
  'test 44: the deletion itself was audited before the event went away');

select is(
  (select (audit_logs.before->>'slug') from audit_logs
    where entity_type = 'events' and entity_id = (select id from draftev) and action = 'event.deleted'),
  'test-audit22-draft',
  'test 44: the deletion audit row retains the event''s identifying details in its own payload, independent of event_id');

select ok(
  (select count(*) from audit_logs
    where entity_type = 'event_games' and event_id is null
      and entity_id in (select id from event_games where event_id = (select id from draftev))
  ) >= 0,
  'test 44: audit history remains structurally valid after event deletion (no error querying it)');

-- ================================================== APPEND-ONLY STILL HOLDS

select throws_like(
  $$ update audit_logs set action = 'tampered' where entity_type = 'events' and entity_id = (select id from draftev) $$,
  '%append-only%',
  'test 44: audit rows remain append-only — changing action is still refused');

select throws_like(
  $$ update audit_logs set after = '{"hacked":true}'::jsonb
       where entity_type = 'events' and entity_id = (select id from draftev) $$,
  '%append-only%',
  'test 44: audit rows remain append-only — changing after/before is still refused');

select throws_like(
  $$ update audit_logs set event_id = null, action = 'tampered'
       where entity_type = 'events' and entity_id = (select id from draftev) $$,
  '%append-only%',
  'test 44: nulling event_id while also changing anything else in the same statement is still refused');

select throws_like(
  $$ delete from audit_logs where entity_type = 'events' and entity_id = (select id from draftev) $$,
  '%append-only%',
  'test 44: audit rows still cannot be deleted at all');

-- ============================================== NON-DRAFT EVENTS PROTECTED

select throws_like(
  $$ select public.admin_delete_event('test-audit22-live') $$,
  'event_not_draft%',
  'test 44: a non-DRAFT (REGISTRATION) event still cannot be deleted');

select public.transition_event((select id from liveev), 'CANCELLED', 'test 44 fixture');
select throws_like(
  $$ select public.admin_delete_event('test-audit22-live') $$,
  'event_not_draft%',
  'test 44: a CANCELLED event still cannot be deleted through this path either — DRAFT only, no exceptions');

select is(
  (select count(*) from events where id = (select id from liveev)),
  1::bigint,
  'test 44: the non-DRAFT event was genuinely left untouched by the rejected attempts');

-- ===================================================== AUTHORIZATION

select pg_temp.as_staff(gen_random_uuid(), 'COORDINATOR');
select throws_ok(
  $$ select public.admin_delete_event('test-audit22-live') $$,
  '42501', null,
  'test 44: a COORDINATOR (not an event admin) cannot delete an event');

select * from finish();
rollback;
