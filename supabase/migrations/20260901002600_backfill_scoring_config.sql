-- 0026 — backfill: correct scoring_config on rows that already existed
-- before Phase 7's seed.sql fix.
--
-- seed.sql's games/event_games inserts use `on conflict ... do nothing`
-- (by slug, and by (event_id, game_id) respectively) — deliberately, so a
-- reseed never clobbers real operational data. That means the Phase 7
-- correction to seed.sql (crewmate win=1/impostor win=2, not the stale
-- 2/4; a minimal {"type":"placement"} marker for Skribbl/Trivia instead of
-- the obsolete fixed-point-bands config) only ever takes effect for a
-- brand-new bootstrap. It does nothing for a `games`/`event_games` row
-- that was inserted before this phase — which is exactly recess-01's
-- current production state: real rows, already carrying real
-- registrations, with `scoring_config = '{}'` on all three configured
-- games.
--
-- This migration is the only thing that actually reaches those existing
-- rows. `db push` applies migrations to existing data; reseeding does not.
--
-- Merges the correct keys in with `||` rather than replacing the column
-- outright, and only touches rows that don't already carry the key it's
-- adding — safe to apply even if some other admin action has since set
-- something here, and safe if this migration is ever re-run.

update public.games
   set default_scoring_config = default_scoring_config || jsonb_build_object(
         'awards', jsonb_build_object(
           'crewmate', jsonb_build_object('win', 1, 'loss', 0),
           'impostor', jsonb_build_object('win', 2, 'loss', 0)
         )
       )
 where slug = 'among-us'
   and not (default_scoring_config ? 'awards');

update public.games
   set default_scoring_config = default_scoring_config || jsonb_build_object('type', 'placement')
 where slug in ('skribbl', 'trivia')
   and not (default_scoring_config ? 'type');

-- The library default above only affects a game added to a *future* event.
-- Every already-configured event_game (recess-01's among-us/skribbl/trivia
-- among them) needs the same correction applied directly, event by event.
update public.event_games eg
   set scoring_config = eg.scoring_config || jsonb_build_object(
         'awards', jsonb_build_object(
           'crewmate', jsonb_build_object('win', 1, 'loss', 0),
           'impostor', jsonb_build_object('win', 2, 'loss', 0)
         )
       )
  from public.games g
 where eg.game_id = g.id
   and g.slug = 'among-us'
   and not (eg.scoring_config ? 'awards');

update public.event_games eg
   set scoring_config = eg.scoring_config || jsonb_build_object('type', 'placement')
  from public.games g
 where eg.game_id = g.id
   and g.slug in ('skribbl', 'trivia')
   and not (eg.scoring_config ? 'type');
