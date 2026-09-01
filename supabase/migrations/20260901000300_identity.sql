-- 0003 — identity. Gate A revision 3, §2.1 and §2.2.

create table public.players (
  id              uuid primary key default gen_random_uuid(),
  phone_e164      text not null,
  real_name       text not null,
  canonical_alias text,
  first_seen_at   timestamptz not null default now(),
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now(),

  constraint players_phone_e164_format check (phone_e164 ~ '^\+[1-9][0-9]{6,14}$'),
  constraint players_real_name_length  check (length(btrim(real_name)) between 1 and 120),
  constraint players_phone_e164_key    unique (phone_e164)
);

create trigger players_set_updated_at
  before update on public.players
  for each row execute function public.set_updated_at();

create table public.staff_profiles (
  user_id    uuid primary key references auth.users (id) on delete cascade,
  name       text not null,
  role       public.staff_role not null default 'COORDINATOR',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),

  constraint staff_profiles_name_length check (length(btrim(name)) between 1 and 120)
);

create trigger staff_profiles_set_updated_at
  before update on public.staff_profiles
  for each row execute function public.set_updated_at();
