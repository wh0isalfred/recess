-- Tests 5, 5b, 5c, 6, 6b, 6c, 7, 7b, 8 — the event state machine.
begin;
select plan(20);

create temporary table t as select id from public.events where slug = 'recess-01';

-- Registration closes 2026-09-11 18:00+01. Tests that need a shut window move
-- the timestamp rather than waiting for the clock.

-- ---- test 5 [r2]: REGISTRATION -> CHECK_IN directly ----------------------
select is((select status::text from public.events where slug='recess-01'),
  'REGISTRATION', 'test 5: seed starts in REGISTRATION');

select lives_ok(
  $$ select public.transition_event((select id from t), 'CHECK_IN') $$,
  'test 5: REGISTRATION -> CHECK_IN is legal without closing registration first');

select is((select status::text from public.events where slug='recess-01'),
  'CHECK_IN', 'test 5: status changed');
select is((select state_version from public.events where slug='recess-01'),
  2::bigint, 'test 5: state_version incremented by exactly 1');
select is((select count(*)::int from public.audit_logs where action='event.status_changed'),
  1, 'test 5: exactly one audit row written');
select is(
  (select before->>'status' || '->' || (after->>'status')
     from public.audit_logs where action='event.status_changed'),
  'REGISTRATION->CHECK_IN', 'test 5: audit row records before and after');

-- ---- test 5b [r2]: the registration window survives check-in -------------
select ok(
  (select registration_closes_at > now() from public.events where slug='recess-01'),
  'test 5b: registration is still open while the event is in CHECK_IN');

-- ---- test 5c [r2]: closing early is a data edit, not a transition --------
-- Pin registration_opens_at into the past so the test does not depend on the
-- hour it runs at; the seed window opens at 12:00 WAT on the current day.
update public.events set registration_opens_at = now() - interval '1 hour'
  where slug = 'recess-01';
select lives_ok(
  $$ update public.events set registration_closes_at = now() where slug='recess-01' $$,
  'test 5c: registration_closes_at can be moved during CHECK_IN');
select is((select status::text from public.events where slug='recess-01'),
  'CHECK_IN', 'test 5c: status is unchanged, so check-in is still possible');

-- ---- test 6: illegal transition rejected ---------------------------------
select throws_ok(
  $$ select public.transition_event((select id from t), 'DRAFT') $$,
  '23514', null, 'test 6: CHECK_IN -> DRAFT is refused');
select is((select status::text from public.events where slug='recess-01'),
  'CHECK_IN', 'test 6: status unchanged after a refused transition');
select is((select state_version from public.events where slug='recess-01'),
  2::bigint, 'test 6: state_version unchanged after a refused transition');
select is((select count(*)::int from public.audit_logs where action='event.status_changed'),
  1, 'test 6: no audit row written for a refused transition');

-- ---- test 6b [r2]: premature close rejected ------------------------------
update public.events set registration_closes_at = now() + interval '1 day' where slug='recess-01';
select throws_ok(
  $$ select public.transition_event((select id from t), 'REGISTRATION_CLOSED') $$,
  '23514', null, 'test 6b: cannot close registration while the window is open');

-- ---- test 7b [r3]: incomplete room configuration blocks CHECK_IN ---------
-- Return to REGISTRATION, null out one room capacity, try to reopen check-in.
select lives_ok(
  $$ select public.transition_event((select id from t), 'REGISTRATION') $$,
  'test 7b: back to REGISTRATION (nobody has checked in)');
update public.rooms set capacity = null
  where label = 'ROOM 02' and event_id = (select id from t);
select throws_ok(
  $$ select public.transition_event((select id from t), 'CHECK_IN') $$,
  '23514', null, 'test 7b: a room with no capacity blocks CHECK_IN');
update public.rooms set capacity = 15
  where label = 'ROOM 02' and event_id = (select id from t);
select lives_ok(
  $$ select public.transition_event((select id from t), 'CHECK_IN') $$,
  'test 7b: CHECK_IN opens once every room has a capacity');

-- ---- test 7: missing rooms blocks CHECK_IN -------------------------------
select lives_ok(
  $$ select public.transition_event((select id from t), 'REGISTRATION') $$,
  'test 7: back to REGISTRATION');
delete from public.rooms where event_id = (select id from t);
select throws_ok(
  $$ select public.transition_event((select id from t), 'CHECK_IN') $$,
  '23514', null, 'test 7: no rooms blocks CHECK_IN');

-- ---- test 8: direct status UPDATE is refused, even as the owner ----------
select throws_ok(
  $$ update public.events set status = 'LIVE' where slug = 'recess-01' $$,
  '23001', null, 'test 8: events.status may only change through transition_event()');

select * from finish();
rollback;
