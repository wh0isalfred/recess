-- 0001 — extensions and shared trigger helpers
-- Gate A revision 3, §12.

create extension if not exists pgcrypto with schema extensions;

-- Maintains updated_at on the mutable tables. One implementation, attached
-- explicitly to each table that has the column.
create or replace function public.set_updated_at()
returns trigger language plpgsql as $$
begin
  new.updated_at := now();
  return new;
end;
$$;

-- Blanket refusals for append-only tables.
create or replace function public.refuse_delete()
returns trigger language plpgsql as $$
begin
  raise exception 'rows in % are append-only and cannot be deleted', tg_table_name
    using errcode = 'restrict_violation';
end;
$$;

create or replace function public.refuse_update()
returns trigger language plpgsql as $$
begin
  raise exception 'rows in % are append-only and cannot be updated', tg_table_name
    using errcode = 'restrict_violation';
end;
$$;

-- point_transactions may only ever be voided. Nothing else about a ledger
-- entry can change, and a voided entry cannot be un-voided.
create or replace function public.ledger_update_guard()
returns trigger language plpgsql as $$
begin
  if old.voided_at is not null then
    raise exception 'point_transactions row % is already voided and is immutable', old.id
      using errcode = 'restrict_violation';
  end if;

  if (new.id, new.event_id, new.registration_id, new.points, new.source,
      new.result_id, new.round_id, new.event_game_id, new.note,
      new.created_by, new.created_at)
     is distinct from
     (old.id, old.event_id, old.registration_id, old.points, old.source,
      old.result_id, old.round_id, old.event_game_id, old.note,
      old.created_by, old.created_at)
  then
    raise exception 'point_transactions is append-only; only voided_at/voided_by may be set'
      using errcode = 'restrict_violation';
  end if;

  if new.voided_at is null then
    raise exception 'the only permitted update to point_transactions is voiding'
      using errcode = 'restrict_violation';
  end if;

  return new;
end;
$$;

-- results may only ever be superseded. A correction inserts a new version.
create or replace function public.results_update_guard()
returns trigger language plpgsql as $$
begin
  if old.superseded_at is not null then
    raise exception 'results row % is already superseded and is immutable', old.id
      using errcode = 'restrict_violation';
  end if;

  if (new.id, new.event_id, new.round_id, new.template, new.payload, new.version,
      new.idempotency_key, new.submitted_by, new.submitted_at, new.created_at)
     is distinct from
     (old.id, old.event_id, old.round_id, old.template, old.payload, old.version,
      old.idempotency_key, old.submitted_by, old.submitted_at, old.created_at)
  then
    raise exception 'results is append-only; only superseded_at/superseded_by may be set'
      using errcode = 'restrict_violation';
  end if;

  if new.superseded_at is null then
    raise exception 'the only permitted update to results is supersession'
      using errcode = 'restrict_violation';
  end if;

  return new;
end;
$$;
