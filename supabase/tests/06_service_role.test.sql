-- Test 15 — service_role reads data, proving RLS is enabled rather than the
-- tables merely being empty.
begin;
select plan(3);

set local role service_role;
select is((select count(*)::int from public.events), 1,
  'test 15: service_role reads the event');
select is((select count(*)::int from public.games), 3,
  'test 15: service_role reads the game library');
select is((select count(*)::int from public.rooms), 2,
  'test 15: service_role reads the rooms');
reset role;

select * from finish();
rollback;
