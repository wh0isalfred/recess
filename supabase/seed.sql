-- RECESS — development seed. Gate A revision 3, §9.
--
-- Run by `supabase db reset` only. Idempotent, so the production bootstrap can
-- reuse it safely. NOT a migration: migrations contain no
-- INSERT statements so a reset stays reproducible and production never
-- receives demo rows by migration.
--
-- Production is bootstrapped deliberately from seeds/production-recess-01.sql.

-- ------------------------------------------------------------ game library

insert into public.games (
  slug, name, description, platform, platform_url, requires_install,
  min_players, max_players, scoring_template, default_round_count,
  default_scoring_config
) values

('among-us', 'Among Us',
 'Hidden role. Crew finish tasks, impostors do not.',
 'INSTALL', null, true, 4, 15, 'ROLE_OUTCOME', 4,
 jsonb_build_object(
   'type', 'role_outcome',
   'roles', jsonb_build_array(
     jsonb_build_object('key','crewmate','label','Crewmate','is_default',true),
     jsonb_build_object('key','impostor','label','Impostor')
   ),
   -- A supported RANGE and no default. There is no impostor count anywhere in
   -- RECESS; actual composition is chosen per round by later domain logic.
   'composition', jsonb_build_object(
     'impostor', jsonb_build_object('min', 1, 'max', 3)
   ),
   'awards', jsonb_build_object(
     'crewmate', jsonb_build_object('win', 2, 'loss', 0),
     'impostor', jsonb_build_object('win', 4, 'loss', 0)
   )
 )),

('skribbl', 'Skribbl',
 'Draw and guess. Placement by score at the end of the lobby.',
 'BROWSER', 'https://skribbl.io', false, 2, 20, 'PLACEMENT', 1,
 jsonb_build_object(
   'type', 'placement',
   '_status', 'PLACEHOLDER — not approved RECESS #1 scoring. See ROADMAP Phase 7.',
   'bands', jsonb_build_array(
     jsonb_build_object('from',1,'to',1,'points',10),
     jsonb_build_object('from',2,'to',2,'points',7),
     jsonb_build_object('from',3,'to',3,'points',5),
     jsonb_build_object('from',4,'to',4,'points',3),
     jsonb_build_object('from',5,'to',5,'points',2),
     jsonb_build_object('from',6,'to',10,'points',1)
   ),
   'unplaced_points', 0,
   'tie_rule', 'SHARED_POSITION'
 )),

('trivia', 'Trivia',
 'Kahoot-style. Everyone reunites for the finale.',
 'BROWSER', 'https://kahoot.it', false, 2, 60, 'PLACEMENT', 1,
 jsonb_build_object(
   'type', 'placement',
   '_status', 'PLACEHOLDER — not approved RECESS #1 scoring. See ROADMAP Phase 7.',
   'bands', jsonb_build_array(
     jsonb_build_object('from',1,'to',1,'points',10),
     jsonb_build_object('from',2,'to',2,'points',7),
     jsonb_build_object('from',3,'to',3,'points',5),
     jsonb_build_object('from',4,'to',4,'points',3),
     jsonb_build_object('from',5,'to',5,'points',2),
     jsonb_build_object('from',6,'to',10,'points',1)
   ),
   'unplaced_points', 0,
   'tie_rule', 'SHARED_POSITION'
 ))
on conflict (slug) do nothing;

-- ---------------------------------------------------------- the edition

insert into public.events (
  slug, name, status,
  starts_at, timezone, timezone_label,
  registration_opens_at, registration_closes_at,
  checkin_opens_at, checkin_closes_at,
  capacity, whatsapp_group_url, leaderboard_visibility
) values (
  'recess-01',
  'RECESS — September 2026',
  'REGISTRATION',
  timestamptz '2026-09-11 20:00:00+01', 'Africa/Lagos', 'WAT',
  timestamptz '2026-09-01 12:00:00+01',
  timestamptz '2026-09-11 18:00:00+01',
  timestamptz '2026-09-11 19:30:00+01',
  timestamptz '2026-09-11 21:30:00+01',
  -- Seed configuration for one edition. NOT a product constant and NOT a
  -- ceiling: the only schema rule is capacity > 0.
  30,
  null,
  'BETWEEN_GAMES'
)
on conflict (slug) do nothing;

-- event_counters is created by trigger; nothing to insert.

-- ------------------------------------------------- games in this edition
-- Library defaults are copied in, exactly as an admin adding a game would.

insert into public.event_games (
  event_id, game_id, position, scoring_template, scoring_config,
  planned_rounds, room_capacity
)
select e.id, g.id, x.position, g.scoring_template, g.default_scoring_config,
       x.rounds, x.room_capacity
from public.events e
join (values
  ('skribbl',  1, 1, 20),
  ('among-us', 2, 4, 15),
  ('trivia',   3, 1, 30)
) as x(slug, position, rounds, room_capacity) on true
join public.games g on g.slug = x.slug
where e.slug = 'recess-01'
on conflict (event_id, game_id) do nothing;

-- ------------------------------------------------------------------ rooms
-- Containers only. Membership is assigned at check-in, from people who
-- actually showed up. Sequential fill by position is Phase 6.

insert into public.rooms (event_id, label, position, capacity)
select e.id, x.label, x.position, x.capacity
from public.events e
join (values
  ('ROOM 01', 1, 15),
  ('ROOM 02', 2, 15)
) as x(label, position, capacity) on true
where e.slug = 'recess-01'
on conflict (event_id, label) do nothing;
