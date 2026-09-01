-- 0004 — events, counters and their guards. Gate A revision 3, §2.3, §2.4, §3.

create table public.events (
  id                     uuid primary key default gen_random_uuid(),
  slug                   text not null,
  name                   text not null,
  status                 public.event_status not null default 'DRAFT',
  state_version          bigint not null default 1,

  starts_at              timestamptz not null,
  timezone               text not null default 'Africa/Lagos',
  timezone_label         text not null default 'WAT',

  registration_opens_at  timestamptz,
  registration_closes_at timestamptz,
  checkin_opens_at       timestamptz,
  checkin_closes_at      timestamptz,

  capacity               integer not null,
  whatsapp_group_url     text,
  leaderboard_visibility public.leaderboard_visibility not null default 'BETWEEN_GAMES',

  results_published_at   timestamptz,
  created_by             uuid references auth.users (id) on delete set null,
  created_at             timestamptz not null default now(),
  updated_at             timestamptz not null default now(),

  constraint events_slug_format check (slug ~ '^[a-z0-9]+(-[a-z0-9]+)*$'),
  -- Lower bound only. There is deliberately no upper bound: capacity is pure
  -- configuration and no number is a RECESS limit. See §2.3 [r2].
  constraint events_capacity_positive check (capacity > 0),
  constraint events_registration_window check (
    registration_opens_at is null or registration_closes_at is null
    or registration_opens_at < registration_closes_at
  ),
  constraint events_checkin_window check (
    checkin_opens_at is null or checkin_closes_at is null
    or checkin_opens_at < checkin_closes_at
  ),
  constraint events_whatsapp_url_https check (
    whatsapp_group_url is null or whatsapp_group_url ~ '^https://'
  ),
  constraint events_slug_key unique (slug),
  constraint events_id_status_key unique (id, status)
);

create index events_status_starts_idx on public.events (status, starts_at);

create trigger events_set_updated_at
  before update on public.events
  for each row execute function public.set_updated_at();

-- Timezone cannot be a CHECK: pg_timezone_names is not immutable. §11.8.
create or replace function public.validate_event_timezone()
returns trigger language plpgsql as $$
begin
  if not exists (select 1 from pg_timezone_names where name = new.timezone) then
    raise exception '% is not a valid IANA timezone name', new.timezone
      using errcode = 'check_violation';
  end if;
  return new;
end;
$$;

create trigger events_validate_timezone
  before insert or update of timezone on public.events
  for each row execute function public.validate_event_timezone();

-- Nothing past DRAFT may be deleted. This single guard is what makes the wide
-- cascade from events safe; see §3, "the load-bearing guard".
create or replace function public.events_draft_only_delete()
returns trigger language plpgsql as $$
begin
  if old.status <> 'DRAFT' then
    raise exception 'event % is % and cannot be deleted; cancel it instead', old.slug, old.status
      using errcode = 'restrict_violation';
  end if;
  return old;
end;
$$;

create trigger events_refuse_delete_unless_draft
  before delete on public.events
  for each row execute function public.events_draft_only_delete();

create table public.event_counters (
  event_id       uuid primary key references public.events (id) on delete cascade,
  next_player_no integer not null default 1,

  constraint event_counters_next_positive check (next_player_no > 0)
);

-- The pair can never drift apart. §5.25.
create or replace function public.create_event_counter()
returns trigger language plpgsql as $$
begin
  insert into public.event_counters (event_id) values (new.id);
  return new;
end;
$$;

create trigger events_create_counter
  after insert on public.events
  for each row execute function public.create_event_counter();
