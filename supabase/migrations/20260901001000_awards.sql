-- 0010 — awards. Gate A revision 3, §2.15, §2.16.
--
-- There is no is_competitive column and no points column. The guarantee that
-- an award can never become a point is structural: point_transactions has no
-- award_id column and no foreign key to this table. §5.16.

create table public.awards (
  id          uuid primary key default gen_random_uuid(),
  event_id    uuid not null references public.events (id) on delete cascade,
  name        text not null,
  description text,
  icon_url    text,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now(),

  constraint awards_name_length check (length(btrim(name)) between 1 and 80),
  constraint awards_id_event_key unique (id, event_id)
);

create unique index awards_event_name_key on public.awards (event_id, lower(name));

create trigger awards_set_updated_at
  before update on public.awards
  for each row execute function public.set_updated_at();

create table public.award_recipients (
  id              uuid primary key default gen_random_uuid(),
  event_id        uuid not null,
  award_id        uuid not null,
  registration_id uuid not null,
  note            text,
  created_at      timestamptz not null default now(),

  constraint award_recipients_award_fkey foreign key (award_id, event_id)
    references public.awards (id, event_id) on delete cascade,
  constraint award_recipients_registration_fkey foreign key (registration_id, event_id)
    references public.event_registrations (id, event_id) on delete restrict,
  constraint award_recipients_key unique (award_id, registration_id)
);
