-- 0005 — event registrations. Gate A revision 3, §2.5.

create table public.event_registrations (
  id            uuid primary key default gen_random_uuid(),
  event_id      uuid not null references public.events (id) on delete cascade,
  player_id     uuid not null references public.players (id) on delete restrict,
  alias         text not null,
  player_number integer not null,
  status        public.registration_status not null default 'REGISTERED',
  checked_in_at timestamptz,
  -- Deliberately NOT a foreign key to auth.users: anonymous session rows are
  -- outside our lifecycle control and a cascade from Supabase auth cleanup
  -- must never delete a registration mid-event. §2.5.
  auth_user_id  uuid,
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now(),

  constraint event_registrations_number_positive check (player_number > 0),
  constraint event_registrations_alias_trimmed  check (alias = btrim(alias)),
  constraint event_registrations_alias_length   check (length(alias) between 2 and 24),
  constraint event_registrations_alias_charset  check (alias ~ '^[A-Za-z0-9._-]+$'),
  constraint event_registrations_event_player_key unique (event_id, player_id),
  constraint event_registrations_event_number_key unique (event_id, player_number),
  constraint event_registrations_id_event_key     unique (id, event_id)
);

-- Case-insensitive alias uniqueness within an event. Stored as typed. §6.5.
create unique index event_registrations_alias_key
  on public.event_registrations (event_id, lower(alias));

create unique index event_registrations_auth_user_key
  on public.event_registrations (auth_user_id) where auth_user_id is not null;

create index event_registrations_event_status_idx
  on public.event_registrations (event_id, status);

create trigger event_registrations_set_updated_at
  before update on public.event_registrations
  for each row execute function public.set_updated_at();
