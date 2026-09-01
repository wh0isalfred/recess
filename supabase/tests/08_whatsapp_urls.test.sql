-- Tests 33-35 — WhatsApp group invite URL validation on both columns.
begin;
select plan(14);

create temporary table t as select id as event_id from public.events where slug='recess-01';

-- ---- test 33: valid invite URLs accepted --------------------------------
select lives_ok(
  $$ update public.events set whatsapp_group_url = 'https://chat.whatsapp.com/BxYz09KLmnOpQrStUv12'
      where slug = 'recess-01' $$,
  'test 33: a valid WhatsApp group invite URL is accepted on events');

select lives_ok(
  $$ update public.rooms set whatsapp_group_url = 'https://chat.whatsapp.com/AbCdEf1234567890GhIj'
      where label = 'ROOM 01' and event_id = (select event_id from t) $$,
  'test 33: a valid WhatsApp group invite URL is accepted on rooms');

select lives_ok(
  $$ update public.rooms set whatsapp_group_url = 'https://chat.whatsapp.com/invite/AbCdEf1234567890'
      where label = 'ROOM 02' and event_id = (select event_id from t) $$,
  'test 33: the older /invite/ form is accepted');

-- ---- test 34: NULL accepted ---------------------------------------------
select lives_ok(
  $$ update public.rooms set whatsapp_group_url = null where event_id = (select event_id from t) $$,
  'test 34: a room with no WhatsApp link is accepted');
select lives_ok(
  $$ update public.events set whatsapp_group_url = null where slug = 'recess-01' $$,
  'test 34: an event with no WhatsApp link is accepted');
select is((select count(*)::int from public.rooms where whatsapp_group_url is null), 2,
  'test 34: the seed rooms carry no link and remain valid');

-- ---- test 35: bad URLs rejected -----------------------------------------
select throws_ok(
  $$ update public.rooms set whatsapp_group_url = 'http://chat.whatsapp.com/AbCdEf1234567890GhIj'
      where label = 'ROOM 01' and event_id = (select event_id from t) $$,
  '23514', null, 'test 35: http:// is rejected on rooms');

select throws_ok(
  $$ update public.rooms set whatsapp_group_url = 'https://example.com/AbCdEf1234567890GhIj'
      where label = 'ROOM 01' and event_id = (select event_id from t) $$,
  '23514', null, 'test 35: an arbitrary https host is rejected');

select throws_ok(
  $$ update public.rooms set whatsapp_group_url = 'https://chat.whatsapp.com.example.com/AbCdEf1234'
      where label = 'ROOM 01' and event_id = (select event_id from t) $$,
  '23514', null, 'test 35: a lookalike host is rejected');

select throws_ok(
  $$ update public.rooms set whatsapp_group_url = 'https://chat.whatsapp.com/'
      where label = 'ROOM 01' and event_id = (select event_id from t) $$,
  '23514', null, 'test 35: an invite URL with no code is rejected');

select throws_ok(
  $$ update public.events set whatsapp_group_url = 'https://example.com/group'
      where slug = 'recess-01' $$,
  '23514', null, 'test 35: the event field follows the same validation');

select throws_ok(
  $$ update public.events set whatsapp_group_url = 'http://chat.whatsapp.com/AbCdEf1234567890GhIj'
      where slug = 'recess-01' $$,
  '23514', null, 'test 35: http:// is rejected on events too');

-- ---- test 36: a missing room link does not block CHECK_IN ---------------
update public.rooms set whatsapp_group_url = null where event_id = (select event_id from t);
select lives_ok(
  $$ select public.transition_event((select event_id from t), 'CHECK_IN') $$,
  'test 36: rooms with no WhatsApp link do not block CHECK_IN');

-- ---- test 37: capacity still blocks CHECK_IN ----------------------------
select public.transition_event((select event_id from t), 'REGISTRATION');
update public.rooms
   set whatsapp_group_url = 'https://chat.whatsapp.com/AbCdEf1234567890GhIj',
       capacity = null
 where label = 'ROOM 02' and event_id = (select event_id from t);
select throws_ok(
  $$ select public.transition_event((select event_id from t), 'CHECK_IN') $$,
  '23514', null, 'test 37: a room with a link but no capacity still blocks CHECK_IN');

select * from finish();
rollback;
