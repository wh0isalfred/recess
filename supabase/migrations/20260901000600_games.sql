-- 0006 — game library and per-edition game configuration.
-- Gate A revision 3, §2.6, §2.7, §8.

create table public.games (
  id                     uuid primary key default gen_random_uuid(),
  slug                   text not null,
  name                   text not null,
  description            text,
  icon_url               text,
  platform               public.game_platform not null,
  platform_url           text,
  requires_install       boolean not null default false,
  min_players            integer,
  max_players            integer,
  scoring_template       public.scoring_template not null,
  default_scoring_config jsonb not null default '{}'::jsonb,
  default_round_count    integer not null default 1,
  instructions           text,
  status                 public.game_status not null default 'ACTIVE',
  created_at             timestamptz not null default now(),
  updated_at             timestamptz not null default now(),

  constraint games_slug_format         check (slug ~ '^[a-z0-9]+(-[a-z0-9]+)*$'),
  constraint games_min_players_positive check (min_players is null or min_players > 0),
  constraint games_player_range        check (
    max_players is null or min_players is null or max_players >= min_players
  ),
  constraint games_round_count_positive check (default_round_count > 0),
  constraint games_config_is_object     check (jsonb_typeof(default_scoring_config) = 'object'),
  constraint games_install_matches_platform check (
    platform = 'INSTALL' or requires_install = false
  ),
  constraint games_slug_key unique (slug)
);

create index games_active_idx on public.games (status) where status = 'ACTIVE';

create trigger games_set_updated_at
  before update on public.games
  for each row execute function public.set_updated_at();

-- Library defaults are COPIED here when a game is added to an event. Nothing
-- reads the library at scoring time. §8.
create table public.event_games (
  id               uuid primary key default gen_random_uuid(),
  event_id         uuid not null references public.events (id) on delete cascade,
  game_id          uuid not null references public.games (id) on delete restrict,
  position         integer not null,
  display_name     text,
  scoring_template public.scoring_template not null,
  scoring_config   jsonb not null default '{}'::jsonb,
  planned_rounds   integer not null default 1,
  -- The lobby limit of THIS GAME. Not rooms.capacity, which is how many
  -- players belong to a RECESS room. §2.9.1.
  room_capacity    integer,
  status           public.event_game_status not null default 'PENDING',
  started_at       timestamptz,
  ended_at         timestamptz,
  created_at       timestamptz not null default now(),
  updated_at       timestamptz not null default now(),

  constraint event_games_position_positive check (position > 0),
  constraint event_games_rounds_positive   check (planned_rounds > 0),
  constraint event_games_room_capacity_positive check (
    room_capacity is null or room_capacity > 0
  ),
  constraint event_games_config_is_object check (jsonb_typeof(scoring_config) = 'object'),
  constraint event_games_ended_needs_start check (ended_at is null or started_at is not null),
  constraint event_games_ended_after_start check (ended_at is null or ended_at >= started_at),
  constraint event_games_event_game_key unique (event_id, game_id),
  constraint event_games_id_event_key   unique (id, event_id)
);

-- Deferred so a reorder can be several UPDATEs in one transaction. §2.7.
alter table public.event_games
  add constraint event_games_position_key unique (event_id, position)
  deferrable initially deferred;

create trigger event_games_set_updated_at
  before update on public.event_games
  for each row execute function public.set_updated_at();
