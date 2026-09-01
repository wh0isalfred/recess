-- 0014 — game-specific player aliases. Phase 1 follow-up amendment.
--
-- A player's name inside an external game is often not their RECESS alias.
-- This table maps one to the other so a coordinator reading "alfred2009" in an
-- Among Us lobby knows it is WH0ISALFRED, without guessing.
--
-- Owned by (registration_id, event_game_id): the only key where the database
-- can guarantee the game is actually being played at this event. event_id is
-- the composite-FK anchor, the same pattern as every other join table here.

create table public.game_aliases (
  id              uuid primary key default gen_random_uuid(),
  event_id        uuid not null,
  registration_id uuid not null,
  event_game_id   uuid not null,
  -- The external in-game name, stored exactly as typed. Charset is
  -- deliberately looser than event_registrations.alias: external games allow
  -- spaces and punctuation ("Big Al"), and a RECESS identity does not.
  alias           text not null,
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now(),

  constraint game_aliases_alias_trimmed check (alias = btrim(alias)),
  constraint game_aliases_alias_length  check (length(alias) between 1 and 40),
  constraint game_aliases_alias_no_control check (alias !~ '[[:cntrl:]]'),

  constraint game_aliases_registration_fkey foreign key (registration_id, event_id)
    references public.event_registrations (id, event_id) on delete cascade,
  constraint game_aliases_event_game_fkey foreign key (event_game_id, event_id)
    references public.event_games (id, event_id) on delete cascade,

  -- One current alias per player per game slot. No history in the row; see
  -- the audit trigger below.
  constraint game_aliases_registration_game_key unique (registration_id, event_game_id)
);

-- Two players cannot claim the same external name in one game slot: that puts
-- the coordinator back to guessing, which is what this table exists to stop.
-- Case-insensitive, matching how RECESS aliases are compared. Scope is the
-- event game, not the room, because rooms do not exist until check-in and
-- aliases are collected before that.
create unique index game_aliases_name_key
  on public.game_aliases (event_game_id, lower(alias));

create index game_aliases_event_game_idx on public.game_aliases (event_game_id);

create trigger game_aliases_set_updated_at
  before update on public.game_aliases
  for each row execute function public.set_updated_at();

-- An alias is a lookup key, not a competition record, so the row is mutable
-- rather than superseded. History lives in the append-only audit log, which
-- still answers "the result at 20:10 was entered against a different alias".
create or replace function public.audit_game_alias()
returns trigger language plpgsql as $$
declare
  v_row    public.game_aliases := coalesce(new, old);
  v_action text := case tg_op
                     when 'INSERT' then 'game_alias.created'
                     when 'UPDATE' then 'game_alias.changed'
                     else 'game_alias.deleted'
                   end;
begin
  insert into public.audit_logs (
    event_id, actor_user_id, action, entity_type, entity_id, before, after
  ) values (
    -- Resolved through the events table so a cascade delete of a DRAFT event
    -- records the alias removal without a dangling reference.
    (select id from public.events where id = v_row.event_id),
    auth.uid(),
    v_action,
    'game_aliases',
    v_row.id,
    case when tg_op = 'INSERT' then null
         else jsonb_build_object('alias', old.alias) end,
    case when tg_op = 'DELETE' then null
         else jsonb_build_object('alias', new.alias) end
  );
  return coalesce(new, old);
end;
$$;

create trigger game_aliases_audit
  after insert or update or delete on public.game_aliases
  for each row execute function public.audit_game_alias();

-- RLS posture, established explicitly. Migration 0013's grant was
-- point-in-time and does not reach tables created afterwards.
alter table public.game_aliases enable row level security;

grant select, insert, update, delete on public.game_aliases
  to anon, authenticated, service_role;
