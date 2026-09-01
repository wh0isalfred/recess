-- 0007 — rooms, memberships, coordinator assignments.
-- Gate A revision 3, §2.8, §2.9, §2.9.1, §2.10.

create table public.rooms (
  id         uuid primary key default gen_random_uuid(),
  event_id   uuid not null references public.events (id) on delete cascade,
  label      text not null,
  position   integer not null,
  -- RECESS room MEMBERSHIP capacity: how many players belong to this room.
  -- Nullable during configuration; mandatory before CHECK_IN opens (§4).
  -- Not event_games.room_capacity, which is a game's lobby limit. §2.9.1.
  capacity   integer,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),

  constraint rooms_position_positive check (position > 0),
  constraint rooms_capacity_positive check (capacity is null or capacity > 0),
  constraint rooms_label_length      check (length(btrim(label)) between 1 and 40),
  constraint rooms_event_label_key   unique (event_id, label),
  constraint rooms_id_event_key      unique (id, event_id)
);

-- [r3] position drives Phase 6 sequential fill, so admins will reorder rooms.
-- Deferred for the same reason as event_games.position.
alter table public.rooms
  add constraint rooms_position_key unique (event_id, position)
  deferrable initially deferred;

create trigger rooms_set_updated_at
  before update on public.rooms
  for each row execute function public.set_updated_at();

create table public.room_memberships (
  id              uuid primary key default gen_random_uuid(),
  -- Denormalised so the composite foreign keys below can make it structurally
  -- impossible to place event A's player in event B's room. §2.9.
  event_id        uuid not null,
  room_id         uuid not null,
  registration_id uuid not null,
  assigned_at     timestamptz not null default now(),
  left_at         timestamptz,

  constraint room_memberships_left_after_assigned check (
    left_at is null or left_at >= assigned_at
  ),
  constraint room_memberships_room_fkey foreign key (room_id, event_id)
    references public.rooms (id, event_id) on delete cascade,
  constraint room_memberships_registration_fkey foreign key (registration_id, event_id)
    references public.event_registrations (id, event_id) on delete cascade

  -- [r3] There is deliberately NO unique (room_id, registration_id): it would
  -- forbid Room 01 -> Room 02 -> Room 01, which is legitimate history.
);

-- The real rule: at most one ACTIVE membership per player per event. §5.29.
create unique index room_memberships_active_key
  on public.room_memberships (event_id, registration_id) where left_at is null;

create index room_memberships_room_idx on public.room_memberships (room_id) where left_at is null;

create table public.coordinator_assignments (
  id         uuid primary key default gen_random_uuid(),
  event_id   uuid not null references public.events (id) on delete cascade,
  user_id    uuid not null references public.staff_profiles (user_id) on delete cascade,
  room_id    uuid,
  created_at timestamptz not null default now(),

  constraint coordinator_assignments_room_fkey foreign key (room_id, event_id)
    references public.rooms (id, event_id) on delete cascade,
  -- NULLS NOT DISTINCT is what makes the event-wide (room_id IS NULL)
  -- assignment unique. §2.10.
  constraint coordinator_assignments_key
    unique nulls not distinct (event_id, user_id, room_id)
);
