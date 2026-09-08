-- RECESS #1 — PRODUCTION BOOTSTRAP
--
-- Run ONCE, deliberately, against the production project. Not a migration and
-- not run by `supabase db reset`. Committed and reviewed so that no production
-- state depends on someone remembering a manual Dashboard change.
--
--   psql "$PRODUCTION_DATABASE_URL" -f supabase/seeds/production-recess-01.sql
--
-- It includes the development seed, which is idempotent: running this twice
-- inserts nothing the second time.
--
-- The scoring values it carries (via seed.sql) are the locked RECESS #1
-- rules as of Phase 7 — see docs/SCORING.md. Among Us: crewmate win = 1
-- raw, impostor win = 2 raw. Skribbl/Trivia: no per-game bands — every
-- game's final ranking normalizes onto the same 0-20 scale via one
-- universal formula, computed by the scoring engine itself, not sourced
-- from configuration.

\echo 'RECESS #1 production bootstrap'

\ir ../seed.sql

select
  (select count(*) from public.games)                                 as games,
  (select count(*) from public.events where slug = 'recess-01')       as events,
  (select count(*) from public.event_games eg
     join public.events e on e.id = eg.event_id where e.slug='recess-01') as event_games,
  (select count(*) from public.rooms r
     join public.events e on e.id = r.event_id where e.slug='recess-01')  as rooms;
