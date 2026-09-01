-- 0009 — results and the point ledger. Gate A revision 3, §2.13, §2.14.

create table public.results (
  id              uuid primary key default gen_random_uuid(),
  event_id        uuid not null,
  round_id        uuid not null,
  template        public.scoring_template not null,
  payload         jsonb not null,
  version         integer not null default 1,
  idempotency_key text not null,
  submitted_by    uuid references auth.users (id) on delete set null,
  submitted_at    timestamptz not null default now(),
  superseded_at   timestamptz,
  superseded_by   uuid references public.results (id) on delete set null,
  created_at      timestamptz not null default now(),

  constraint results_payload_is_object check (jsonb_typeof(payload) = 'object'),
  constraint results_version_positive  check (version > 0),
  constraint results_idempotency_length check (length(idempotency_key) between 8 and 128),
  constraint results_supersession_pair check (
    (superseded_at is null) = (superseded_by is null)
  ),
  constraint results_round_fkey foreign key (round_id, event_id)
    references public.rounds (id, event_id) on delete cascade,
  -- Globally unique: a double-tap is rejected regardless of which round the
  -- client thought it was submitting to. §2.13.
  constraint results_idempotency_key unique (idempotency_key)
);

-- Exactly one authoritative result per round. Superseded rows remain. §5.11.
create unique index results_authoritative_key
  on public.results (round_id) where superseded_at is null;

create trigger results_refuse_delete
  before delete on public.results
  for each row execute function public.refuse_delete();

create trigger results_update_guard
  before update on public.results
  for each row execute function public.results_update_guard();

create table public.point_transactions (
  id              uuid primary key default gen_random_uuid(),
  event_id        uuid not null,
  registration_id uuid not null,
  points          integer not null,          -- may be negative: manual escape hatch
  source          public.transaction_source not null,
  result_id       uuid references public.results (id) on delete restrict,
  round_id        uuid references public.rounds (id) on delete restrict,
  event_game_id   uuid references public.event_games (id) on delete restrict,
  note            text,
  voided_at       timestamptz,
  voided_by       uuid references auth.users (id) on delete set null,
  created_by      uuid references auth.users (id) on delete set null,
  created_at      timestamptz not null default now(),

  constraint point_transactions_result_needs_source check (
    source <> 'RESULT' or result_id is not null
  ),
  constraint point_transactions_manual_needs_note check (
    source <> 'MANUAL_ADJUSTMENT'
    or (result_id is null and btrim(coalesce(note, '')) <> '')
  ),
  constraint point_transactions_void_needs_actor check (
    voided_at is null or voided_by is not null
  ),
  constraint point_transactions_registration_fkey foreign key (registration_id, event_id)
    references public.event_registrations (id, event_id) on delete restrict
);

-- The standings query.
create index point_transactions_live_idx
  on public.point_transactions (event_id, registration_id) where voided_at is null;

create index point_transactions_result_idx on public.point_transactions (result_id);

-- A single result can never credit the same player twice. §5.13.
create unique index point_transactions_result_player_key
  on public.point_transactions (result_id, registration_id)
  where voided_at is null and source = 'RESULT';

create trigger point_transactions_refuse_delete
  before delete on public.point_transactions
  for each row execute function public.refuse_delete();

create trigger point_transactions_update_guard
  before update on public.point_transactions
  for each row execute function public.ledger_update_guard();
