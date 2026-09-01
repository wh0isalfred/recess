-- 0008 — rounds and participation. Gate A revision 3, §2.11, §2.12.

create table public.rounds (
  id            uuid primary key default gen_random_uuid(),
  event_id      uuid not null,
  event_game_id uuid not null,
  room_id       uuid,                      -- NULL = whole-event round (the finale)
  round_index   integer not null,          -- "index" is reserved
  status        public.round_status not null default 'DRAFT',
  started_at    timestamptz,
  ended_at      timestamptz,
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now(),

  constraint rounds_index_positive     check (round_index > 0),
  constraint rounds_ended_needs_start  check (ended_at is null or started_at is not null),
  constraint rounds_ended_after_start  check (ended_at is null or ended_at >= started_at),
  constraint rounds_event_game_fkey foreign key (event_game_id, event_id)
    references public.event_games (id, event_id) on delete cascade,
  constraint rounds_room_fkey foreign key (room_id, event_id)
    references public.rooms (id, event_id) on delete cascade,
  -- NULLS NOT DISTINCT: no sentinel-UUID trick needed for whole-event rounds.
  constraint rounds_scope_index_key
    unique nulls not distinct (event_game_id, room_id, round_index),
  constraint rounds_id_event_key unique (id, event_id)
);

create trigger rounds_set_updated_at
  before update on public.rounds
  for each row execute function public.set_updated_at();

create table public.round_participants (
  id              uuid primary key default gen_random_uuid(),
  event_id        uuid not null,
  round_id        uuid not null,
  registration_id uuid not null,
  participation   public.participation_state not null default 'PARTICIPATING',
  -- Free text, deliberately not an enum. An enum would encode 'impostor' into
  -- the engine; Werewolf must work without a migration. §2.12, §5.33.
  role_key        text,
  created_at      timestamptz not null default now(),

  constraint round_participants_role_format check (
    role_key is null or role_key ~ '^[a-z][a-z0-9_]{0,31}$'
  ),
  -- DNP is not a loss and carries no role.
  constraint round_participants_dnp_has_no_role check (
    participation = 'PARTICIPATING' or role_key is null
  ),
  constraint round_participants_round_fkey foreign key (round_id, event_id)
    references public.rounds (id, event_id) on delete cascade,
  constraint round_participants_registration_fkey foreign key (registration_id, event_id)
    references public.event_registrations (id, event_id) on delete restrict,
  constraint round_participants_key unique (round_id, registration_id)
);

create index round_participants_role_idx on public.round_participants (round_id, role_key);
