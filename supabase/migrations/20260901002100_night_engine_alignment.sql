-- 0021 — Phase 6.5: Night Engine Alignment.
--
-- Aligns the room/coordinator/game-progression data model with the approved
-- real-world night (docs/EVENT-OPS.md, docs/SCORING.md) ahead of Scoring
-- Engine V1. Five pieces, in the order below:
--
--   1. Registrant-based room coordinators (room_coordinators) — a new,
--      dedicated table. The existing staff-based coordinator_assignments
--      (0007) is left completely alone: it models an EVENT-WIDE staff
--      coordinator concept (room_id nullable) that this slice does not
--      touch and does not need. A real room coordinator is now one of the
--      people who registered for the event, not a staff_profiles row — the
--      two are different people in different tables, and conflating them
--      would have meant either fabricating a staff_profiles row for every
--      coordinator (a real player, not staff) or loosening
--      require_event_admin() in a way the brief explicitly warns against.
--   2. Coordinator seat reservation — derived, not a stored boolean: a
--      room's coordinator "has the reservation" for as long as their own
--      active room_coordinators row exists and they have no active
--      room_membership in that room yet. The moment they check in, their
--      membership row exists and the reservation computation naturally
--      stops counting it as reserved — no separate flag to keep in sync.
--   3. rooms.capacity <= 15, added as a forward constraint after confirming
--      the seed data (both seeded rooms are capacity 15) is compatible.
--   4. room_event_games — the smallest per-room-game progression model:
--      one row per (room, event_game), a three-value status, and two
--      narrow functions (start_room_game / complete_room_game) enforcing
--      "no two LIVE at once per room" and "cannot skip configured order."
--      Named room_event_games rather than a generic "sessions" table
--      because it is exactly what it says: this room's row for this
--      event_game. round_participants/rounds already link to room + game;
--      this table sits one level up, describing the room's progress
--      through the game itself, not any one round.
--   5. event_games.duration_minutes — minutes, not seconds: every duration
--      this schema or EVENT-OPS.md discusses is phrased in whole minutes
--      ("30 minutes"), nothing about a game window needs sub-minute
--      precision, and Admin UI will collect it as a plain minutes input.
--      Also games.default_duration_minutes as a safe, nullable library
--      default, copied at attach time exactly the way default_round_count
--      already copies into planned_rounds (§17) — never a hardcoded
--      per-game number.
--
-- Explicitly NOT in this migration: preview_result/submit_result,
-- championship point calculation, room leaderboards, Coordinator V1 UI,
-- Admin Live Control. Those are Scoring Engine V1 and later.

-- ============================================================ 1. ENUM

create type public.room_game_status as enum ('PENDING', 'LIVE', 'COMPLETE');
-- No RESULT_PENDING: EVENT-OPS.md's round lifecycle (§6) already has its own
-- RESULT ENTRY / PREVIEW / CONFIRMED states for a *round*; adding a parallel
-- state at the room-game level before Scoring Engine V1 exists would be
-- exactly the unnecessary complexity the brief warns against. A room-game
-- is either not started, in progress, or done.

-- ============================================================ 2. TABLES

-- ---------------------------------------------------- room_coordinators

create table public.room_coordinators (
  id              uuid primary key default gen_random_uuid(),
  -- Denormalised for the composite FKs below, same pattern room_memberships
  -- already uses — makes it structurally impossible to assign event A's
  -- registration as coordinator of event B's room.
  event_id        uuid not null references public.events (id) on delete cascade,
  room_id         uuid not null,
  registration_id uuid not null,
  assigned_at     timestamptz not null default now(),
  -- History, not deletion: replacing a coordinator sets replaced_at on the
  -- old row and inserts a new one. §invariant D — Admin replacement must
  -- not require destructive delete, and an audit/history view over "who
  -- coordinated this room" stays honest.
  replaced_at     timestamptz,

  constraint room_coordinators_replaced_after_assigned check (
    replaced_at is null or replaced_at >= assigned_at
  ),
  constraint room_coordinators_room_fkey foreign key (room_id, event_id)
    references public.rooms (id, event_id) on delete cascade,
  constraint room_coordinators_registration_fkey foreign key (registration_id, event_id)
    references public.event_registrations (id, event_id) on delete cascade
);

-- Invariant A: exactly one ACTIVE (replaced_at is null) coordinator per room.
create unique index room_coordinators_one_active_per_room
  on public.room_coordinators (room_id) where replaced_at is null;

-- Invariant B: a registration cannot actively coordinate two rooms in the
-- same event.
create unique index room_coordinators_one_active_per_registration
  on public.room_coordinators (event_id, registration_id) where replaced_at is null;

create index room_coordinators_room_idx on public.room_coordinators (room_id);

alter table public.room_coordinators enable row level security;
grant select, insert, update, delete on public.room_coordinators
  to anon, authenticated, service_role;

comment on table public.room_coordinators is
  'Registrant-based room coordinators (Phase 6.5) — a real event player
   chosen by Admin to run a room, distinct from the staff-based
   coordinator_assignments (0007), which models an event-wide STAFF
   coordinator concept this table does not replace.';

-- --------------------------------------------------------- room_event_games

create table public.room_event_games (
  id            uuid primary key default gen_random_uuid(),
  event_id      uuid not null references public.events (id) on delete cascade,
  room_id       uuid not null,
  event_game_id uuid not null,
  status        public.room_game_status not null default 'PENDING',
  started_at    timestamptz,
  ended_at      timestamptz,
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now(),

  constraint room_event_games_ended_needs_start check (ended_at is null or started_at is not null),
  constraint room_event_games_ended_after_start check (ended_at is null or ended_at >= started_at),
  constraint room_event_games_room_fkey foreign key (room_id, event_id)
    references public.rooms (id, event_id) on delete cascade,
  constraint room_event_games_event_game_fkey foreign key (event_game_id, event_id)
    references public.event_games (id, event_id) on delete cascade,
  constraint room_event_games_key unique (room_id, event_game_id)
);

-- "One room cannot have two different games LIVE simultaneously" as a real
-- constraint, not just application discipline that a direct write could
-- still violate.
create unique index room_event_games_one_live_per_room
  on public.room_event_games (room_id) where status = 'LIVE';

create index room_event_games_event_idx on public.room_event_games (event_id);

create trigger room_event_games_set_updated_at
  before update on public.room_event_games
  for each row execute function public.set_updated_at();

alter table public.room_event_games enable row level security;
grant select, insert, update, delete on public.room_event_games
  to anon, authenticated, service_role;

comment on table public.room_event_games is
  'One row per (room, event_game): this room''s progress through this
   configured game. Rows are created lazily by start_room_game(), not
   pre-seeded — a room that never reaches Trivia never gets a Trivia row.
   Sits above rounds/round_participants (already room+game scoped) as the
   thing that actually says whether the room''s current game is live.';

-- ============================================================ 3. CAPACITY <= 15

-- Compatibility check first, per the brief: do not add a constraint that
-- silently clamps or rejects real existing data without saying so. Both
-- seeded rooms are capacity 15 (supabase/seed.sql) — compatible. If this
-- ever ran against a database with a room >15, the ALTER below would fail
-- loudly with a constraint-violation error naming the row, not silently
-- rewrite it.
do $$
begin
  if exists (select 1 from public.rooms where capacity > 15) then
    raise exception 'incompatible_data: a room with capacity > 15 already exists — resolve manually before this migration can proceed'
      using errcode = '23514';
  end if;
end;
$$;

alter table public.rooms add constraint rooms_capacity_max_15 check (capacity is null or capacity <= 15);

comment on column public.rooms.capacity is
  'RECESS room MEMBERSHIP capacity: how many players belong to this room,
   INCLUDING the coordinator''s reserved seat. 1-15 inclusive (Phase 6.5) —
   Among Us caps lobbies at 15, and RECESS rooms follow that ceiling. Not
   event_games.room_capacity, which is a game''s own lobby limit. §2.9.1.';

-- ============================================================ 4. DURATION

alter table public.games add column default_duration_minutes integer;
alter table public.games add constraint games_default_duration_positive
  check (default_duration_minutes is null or default_duration_minutes > 0);

comment on column public.games.default_duration_minutes is
  'Library default game window, in minutes. Nullable/optional — copied into
   event_games.duration_minutes at attach time exactly the way
   default_round_count copies into planned_rounds (§17); never a hardcoded
   system-wide default. Alfred has not set these yet — see docs/EVENT-OPS.md
   §16, the exact per-game defaults are intentionally unresolved.';

alter table public.event_games add column duration_minutes integer;
alter table public.event_games add constraint event_games_duration_positive
  check (duration_minutes is null or duration_minutes > 0);

comment on column public.event_games.duration_minutes is
  'The intended game window for THIS event''s configuration of this game, in
   minutes (EVENT-OPS.md §5, "the operating contract calls this the game
   window"). Nullable until Admin configures it — a game added to an event
   before its duration is decided is a real, valid, not-yet-fully-configured
   state, same treatment rooms.capacity already gets. The timer itself
   (when it starts, expiry behaviour) is start_room_game()''s concern below,
   not this column — this column is configuration, not a running clock.';

-- ============================================================ 5. FUNCTIONS

-- --------------------------------------------- coordinator candidate list

-- Read-only. Admin-only (candidate aliases/player numbers are not PII, but
-- this is still an Admin operational read, not a public one). Deliberately
-- returns alias + player number only — no phone, no real name — matching
-- the brief's "Alias/name/player number are enough for identification."
create or replace function public.admin_list_coordinator_candidates(p_event_slug text)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
declare
  v_event_id uuid;
begin
  perform public.require_event_admin();

  select id into v_event_id from events where slug = p_event_slug;
  if not found then
    raise exception 'event_not_found: no such event' using errcode = 'no_data_found';
  end if;

  return coalesce((
    select jsonb_agg(jsonb_build_object(
             'registrationId', er.id,
             'alias', er.alias,
             'playerNumber', er.player_number
           ) order by er.player_number)
      from event_registrations er
     where er.event_id = v_event_id
       and er.status = 'REGISTERED'
       and er.checked_in_at is null
       and er.auth_user_id is not null
       and not exists (
         select 1 from room_coordinators rc
          where rc.event_id = v_event_id and rc.registration_id = er.id and rc.replaced_at is null
       )
  ), '[]'::jsonb);
end;
$$;

revoke all on function public.admin_list_coordinator_candidates(text) from public;
grant execute on function public.admin_list_coordinator_candidates(text) to authenticated;

-- ---------------------------------------- shared coordinator eligibility check

-- Used by both admin_create_room and admin_replace_room_coordinator so the
-- eligibility rule is defined exactly once. Raises with a specific message
-- per failure reason rather than one generic "not eligible" — the pgTAP
-- suite (tests 6-10) checks these are distinguishable, and an Admin fixing
-- a rejected room creation needs to know which rule they hit.
create or replace function public.assert_coordinator_eligible(
  p_event_id uuid,
  p_registration_id uuid
) returns void
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
declare
  v_reg record;
begin
  select * into v_reg from event_registrations
   where id = p_registration_id;

  if not found or v_reg.event_id <> p_event_id then
    raise exception 'coordinator_wrong_event: candidate does not belong to this event' using errcode = '23514';
  end if;
  if v_reg.status = 'WAITLISTED' then
    raise exception 'coordinator_waitlisted: a waitlisted registration cannot coordinate' using errcode = '23514';
  end if;
  if v_reg.status = 'CANCELLED' then
    raise exception 'coordinator_cancelled: a cancelled registration cannot coordinate' using errcode = '23514';
  end if;
  if v_reg.checked_in_at is not null then
    raise exception 'coordinator_checked_in: an already checked-in registration cannot become a new coordinator' using errcode = '23514';
  end if;
  if v_reg.auth_user_id is null then
    raise exception 'coordinator_no_session: candidate has no player session' using errcode = '23514';
  end if;
  if exists (
    select 1 from room_coordinators rc
     where rc.event_id = p_event_id and rc.registration_id = p_registration_id and rc.replaced_at is null
  ) then
    raise exception 'coordinator_already_assigned: candidate is already coordinating another room' using errcode = '23514';
  end if;
end;
$$;

revoke all on function public.assert_coordinator_eligible(uuid, uuid) from public;
-- Not granted to authenticated: this is a shared internal check called
-- (with SECURITY DEFINER privilege) by the two admin functions below, not
-- an RPC surface of its own.

-- ------------------------------------------------------------- admin_create_room

-- Atomic room + coordinator creation. This is the ONLY way to create a new
-- operational room from this migration forward — admin_upsert_room (below)
-- stops supporting creation, so there is exactly one path into existence
-- for a room and it always has a coordinator.
create or replace function public.admin_create_room(
  p_event_slug text,
  p_label text,
  p_capacity integer,
  p_coordinator_registration_id uuid,
  p_whatsapp_group_url text default null
) returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_uid uuid := auth.uid();
  v_event_id uuid;
  v_next_position integer;
  v_room public.rooms;
begin
  perform public.require_event_admin();

  select id into v_event_id from events where slug = p_event_slug;
  if not found then
    raise exception 'event_not_found: no such event' using errcode = 'no_data_found';
  end if;

  if btrim(coalesce(p_label, '')) = '' then
    raise exception 'invalid_label: room label is required' using errcode = '22023';
  end if;
  if p_capacity is null or p_capacity <= 0 or p_capacity > 15 then
    raise exception 'invalid_capacity: capacity must be between 1 and 15' using errcode = '22023';
  end if;
  if p_whatsapp_group_url is not null and not public.is_whatsapp_group_url(p_whatsapp_group_url) then
    raise exception 'invalid_whatsapp_url: not a WhatsApp group invite link' using errcode = '22023';
  end if;
  if p_coordinator_registration_id is null then
    raise exception 'coordinator_required: an operational room must have a coordinator' using errcode = '22023';
  end if;

  perform public.assert_coordinator_eligible(v_event_id, p_coordinator_registration_id);

  select coalesce(max(position), 0) + 1 into v_next_position from rooms where event_id = v_event_id;

  insert into rooms (event_id, label, position, capacity, whatsapp_group_url)
  values (v_event_id, btrim(p_label), v_next_position, p_capacity, p_whatsapp_group_url)
  returning * into v_room;

  insert into room_coordinators (event_id, room_id, registration_id)
  values (v_event_id, v_room.id, p_coordinator_registration_id);

  insert into audit_logs (event_id, actor_user_id, action, entity_type, entity_id, after)
  values (v_event_id, v_uid, 'room.created', 'rooms', v_room.id,
          jsonb_build_object('label', v_room.label, 'capacity', v_room.capacity,
                              'coordinatorRegistrationId', p_coordinator_registration_id));

  -- A brand-new room may have ordinary headroom that existing waiting
  -- players can use immediately (EVENT-OPS.md §3, "when the Admin creates
  -- another staffed room, waiting players should fill the newly-available
  -- seats in check-in order"). Reuses the same function Admin would call by
  -- hand — one implementation of "assign waiting players," not two.
  perform public.admin_assign_waiting_players(p_event_slug);

  return jsonb_build_object('roomId', v_room.id, 'label', v_room.label);
end;
$$;

revoke all on function public.admin_create_room(text, text, integer, uuid, text) from public;
grant execute on function public.admin_create_room(text, text, integer, uuid, text) to authenticated;

-- ------------------------------------------------------------- admin_upsert_room

-- Now EDIT-ONLY. Creation moved to admin_create_room above so a room can
-- never come into existence without a coordinator through this function.
create or replace function public.admin_upsert_room(
  p_event_slug text,
  p_room_id    uuid,
  p_label      text,
  p_capacity   integer,
  p_whatsapp_group_url text
) returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_uid uuid := auth.uid();
  v_event_id uuid;
  v_room record;
  v_active_count int;
  v_reserved int;
begin
  perform public.require_event_admin();

  select id into v_event_id from events where slug = p_event_slug;
  if not found then
    raise exception 'event_not_found: no such event' using errcode = 'no_data_found';
  end if;

  if p_room_id is null then
    raise exception 'use_admin_create_room: creating a new room requires a coordinator — call admin_create_room instead'
      using errcode = '22023';
  end if;

  if btrim(coalesce(p_label, '')) = '' then
    raise exception 'invalid_label: room label is required' using errcode = '22023';
  end if;
  if p_capacity is not null and (p_capacity <= 0 or p_capacity > 15) then
    raise exception 'invalid_capacity: capacity must be between 1 and 15' using errcode = '22023';
  end if;
  if p_whatsapp_group_url is not null and not public.is_whatsapp_group_url(p_whatsapp_group_url) then
    raise exception 'invalid_whatsapp_url: not a WhatsApp group invite link' using errcode = '22023';
  end if;

  select * into v_room from rooms where id = p_room_id and event_id = v_event_id for update;
  if not found then
    raise exception 'room_not_found: no such room on this event' using errcode = 'no_data_found';
  end if;

  if p_capacity is not null then
    select count(*) into v_active_count from room_memberships where room_id = p_room_id and left_at is null;
    v_reserved := case when exists (
      select 1 from room_coordinators rc
       where rc.room_id = p_room_id and rc.replaced_at is null
         and not exists (
           select 1 from room_memberships rm
            where rm.room_id = p_room_id and rm.registration_id = rc.registration_id and rm.left_at is null
         )
    ) then 1 else 0 end;

    if p_capacity < v_active_count + v_reserved then
      raise exception 'capacity_below_active: capacity cannot be set below current active membership plus the reserved coordinator seat (% already in use)', v_active_count + v_reserved
        using errcode = '23514';
    end if;
  end if;

  update rooms
     set label = btrim(p_label), capacity = p_capacity, whatsapp_group_url = p_whatsapp_group_url
   where id = p_room_id
   returning * into v_room;

  insert into audit_logs (event_id, actor_user_id, action, entity_type, entity_id, before, after)
  values (v_event_id, v_uid, 'room.updated', 'rooms', v_room.id,
          jsonb_build_object('label', v_room.label),
          jsonb_build_object('label', v_room.label, 'capacity', v_room.capacity, 'whatsapp', v_room.whatsapp_group_url is not null));

  -- A capacity increase can open ordinary seats for people already waiting.
  if p_capacity is not null then
    perform public.admin_assign_waiting_players(p_event_slug);
  end if;

  return jsonb_build_object('id', v_room.id, 'label', v_room.label, 'position', v_room.position,
                             'capacity', v_room.capacity, 'whatsappGroupUrl', v_room.whatsapp_group_url);
end;
$$;

-- ------------------------------------------------- admin_replace_room_coordinator

create or replace function public.admin_replace_room_coordinator(
  p_event_slug text,
  p_room_id uuid,
  p_new_registration_id uuid
) returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_uid uuid := auth.uid();
  v_event_id uuid;
  v_old_id uuid;
begin
  perform public.require_event_admin();

  select id into v_event_id from events where slug = p_event_slug;
  if not found then
    raise exception 'event_not_found: no such event' using errcode = 'no_data_found';
  end if;

  if not exists (select 1 from rooms where id = p_room_id and event_id = v_event_id) then
    raise exception 'room_not_found: no such room on this event' using errcode = 'no_data_found';
  end if;

  perform public.assert_coordinator_eligible(v_event_id, p_new_registration_id);

  -- Old reservation ceases (the partial unique index only guards ACTIVE
  -- rows, so this must happen before the insert below, in the same
  -- transaction, or the new insert would violate
  -- room_coordinators_one_active_per_room).
  update room_coordinators
     set replaced_at = now()
   where room_id = p_room_id and replaced_at is null
   returning id into v_old_id;

  insert into room_coordinators (event_id, room_id, registration_id)
  values (v_event_id, p_room_id, p_new_registration_id);

  insert into audit_logs (event_id, actor_user_id, action, entity_type, entity_id, before, after)
  values (v_event_id, v_uid, 'room.coordinator_replaced', 'rooms', p_room_id,
          jsonb_build_object('previousAssignmentId', v_old_id),
          jsonb_build_object('newRegistrationId', p_new_registration_id));

  return jsonb_build_object('roomId', p_room_id, 'coordinatorRegistrationId', p_new_registration_id);
end;
$$;

revoke all on function public.admin_upsert_room(text, uuid, text, integer, text) from public;
revoke all on function public.admin_replace_room_coordinator(text, uuid, uuid) from public;
grant execute on function public.admin_upsert_room(text, uuid, text, integer, text) to authenticated;
grant execute on function public.admin_replace_room_coordinator(text, uuid, uuid) to authenticated;

-- ------------------------------------------------------------- admin_list_rooms

-- Coordinator now comes from room_coordinators + event_registrations
-- (alias/player number), not coordinator_assignments + staff_profiles.
-- checkedInAt on the coordinator lets the Admin UI show "not checked in
-- yet" vs "checked in" without a second query.
create or replace function public.admin_list_rooms(p_event_slug text)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
declare
  v_event_id uuid;
  v_result jsonb;
begin
  perform public.require_event_admin();

  select id into v_event_id from events where slug = p_event_slug;
  if not found then
    raise exception 'event_not_found: no such event' using errcode = 'no_data_found';
  end if;

  select jsonb_build_object(
    'rooms', (
      select coalesce(jsonb_agg(jsonb_build_object(
               'id', ro.id, 'label', ro.label, 'position', ro.position, 'capacity', ro.capacity,
               'whatsappGroupUrl', ro.whatsapp_group_url,
               'occupancy', (select count(*) from room_memberships where room_id = ro.id and left_at is null),
               'coordinator', (
                 select jsonb_build_object(
                          'registrationId', er.id, 'alias', er.alias, 'playerNumber', er.player_number,
                          'checkedInAt', er.checked_in_at
                        )
                   from room_coordinators rc
                   join event_registrations er on er.id = rc.registration_id
                  where rc.room_id = ro.id and rc.replaced_at is null
                  limit 1
               )
             ) order by ro.position), '[]'::jsonb)
        from rooms ro where ro.event_id = v_event_id
    ),
    'waiting', (
      select coalesce(jsonb_agg(jsonb_build_object(
               'alias', er.alias, 'playerNumber', er.player_number, 'checkedInAt', er.checked_in_at
             ) order by er.checked_in_at), '[]'::jsonb)
        from event_registrations er
       where er.event_id = v_event_id and er.checked_in_at is not null
         and not exists (select 1 from room_memberships rm where rm.registration_id = er.id and rm.left_at is null)
    )
  ) into v_result;

  return v_result;
end;
$$;

-- --------------------------------------------------------------- check_in_player

-- Same shape as 0017's version, with two changes: (1) a coordinator check
-- BEFORE the sequential-fill loop — an active coordinator goes straight to
-- their own room and never enters the loop at all; (2) the loop's own
-- capacity test now subtracts a room's unfulfilled coordinator reservation,
-- so an ordinary player can never take the seat being held for a
-- coordinator who has not checked in yet.
create or replace function public.check_in_player()
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_uid           uuid;
  v_reg           record;
  v_event         record;
  v_room          record;
  v_membership_id uuid;
  v_coordinating_room_id uuid;
  v_reserved      int;
begin
  v_uid := auth.uid();
  if v_uid is null then
    raise exception 'not_authenticated: no player session' using errcode = '28000';
  end if;

  select r.* into v_reg
    from public.event_registrations r
   where r.auth_user_id = v_uid
   order by r.created_at desc
   limit 1;

  if not found then
    raise exception 'not_registered: no registration found for this session' using errcode = 'no_data_found';
  end if;

  if v_reg.status = 'WAITLISTED' then
    raise exception 'waitlisted: waitlisted registrations cannot check in' using errcode = '55000';
  end if;
  if v_reg.status = 'CANCELLED' then
    raise exception 'cancelled: this registration was cancelled' using errcode = '55000';
  end if;

  select * into v_event from public.events where id = v_reg.event_id;

  if v_event.status <> 'CHECK_IN' then
    raise exception 'check_in_not_open: check-in is not open right now' using errcode = '55000';
  end if;
  if v_event.checkin_opens_at is not null and now() < v_event.checkin_opens_at then
    raise exception 'check_in_not_open: check-in has not opened yet' using errcode = '55000';
  end if;
  if v_event.checkin_closes_at is not null and now() >= v_event.checkin_closes_at then
    raise exception 'check_in_closed: check-in has closed' using errcode = '55000';
  end if;

  if v_reg.checked_in_at is not null then
    return public.get_player_state();
  end if;

  update public.event_registrations
     set checked_in_at = now()
   where id = v_reg.id and checked_in_at is null;

  if not found then
    return public.get_player_state();
  end if;

  -- Coordinator path: an active, not-yet-seated coordinator assignment for
  -- this registration goes straight to that room. Locked the same way the
  -- ordinary loop below locks rooms, so a concurrent replacement (which
  -- also touches room_coordinators) cannot race this into assigning the
  -- wrong room.
  select rc.room_id into v_coordinating_room_id
    from room_coordinators rc
   where rc.event_id = v_reg.event_id and rc.registration_id = v_reg.id and rc.replaced_at is null
   for update;

  if v_coordinating_room_id is not null then
    -- Idempotent the same way the ordinary path is: only insert if this
    -- registration has no active membership in this room yet.
    if not exists (
      select 1 from room_memberships
       where room_id = v_coordinating_room_id and registration_id = v_reg.id and left_at is null
    ) then
      insert into public.room_memberships (event_id, room_id, registration_id)
      values (v_reg.event_id, v_coordinating_room_id, v_reg.id)
      returning id into v_membership_id;
    end if;

    insert into public.audit_logs (event_id, actor_user_id, action, entity_type, entity_id, after)
    values (
      v_reg.event_id, v_uid, 'registration.checked_in', 'event_registrations', v_reg.id,
      jsonb_build_object('checked_in_at', now(), 'room_membership_id', v_membership_id, 'asCoordinator', true)
    );

    return public.get_player_state();
  end if;

  -- Ordinary path: strict sequential fill, reservation-aware.
  for v_room in
    select rm.* from public.rooms rm
     where rm.event_id = v_reg.event_id
     order by rm.position
     for update
  loop
    if v_room.capacity is null then
      continue;
    end if;

    v_reserved := case when exists (
      select 1 from room_coordinators rc
       where rc.room_id = v_room.id and rc.replaced_at is null
         and not exists (
           select 1 from room_memberships rm2
            where rm2.room_id = v_room.id and rm2.registration_id = rc.registration_id and rm2.left_at is null
         )
    ) then 1 else 0 end;

    if (
      select count(*) from public.room_memberships
       where room_id = v_room.id and left_at is null
    ) < (v_room.capacity - v_reserved) then
      insert into public.room_memberships (event_id, room_id, registration_id)
      values (v_reg.event_id, v_room.id, v_reg.id)
      returning id into v_membership_id;
      exit;
    end if;
  end loop;

  insert into public.audit_logs (event_id, actor_user_id, action, entity_type, entity_id, after)
  values (
    v_reg.event_id, v_uid, 'registration.checked_in', 'event_registrations', v_reg.id,
    jsonb_build_object('checked_in_at', now(), 'room_membership_id', v_membership_id)
  );

  return public.get_player_state();
end;
$$;

-- ------------------------------------------------------ admin_assign_waiting_players

-- Same reservation-aware capacity test as check_in_player() above. Waiting
-- players are, by construction, never coordinators (a coordinator always
-- gets a direct room assignment the moment they check in — see above — so
-- they can never accumulate in the "checked in, no active membership" set
-- this function scans), so no coordinator-direct-assignment branch is
-- needed here, only the reservation-aware ordinary capacity test.
create or replace function public.admin_assign_waiting_players(p_event_slug text)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_uid uuid := auth.uid();
  v_event record;
  v_reg record;
  v_room record;
  v_membership_id uuid;
  v_reserved int;
  v_assigned int := 0;
  v_still_waiting int := 0;
begin
  perform public.require_event_admin();

  select * into v_event from events where slug = p_event_slug;
  if not found then
    raise exception 'event_not_found: no such event' using errcode = 'no_data_found';
  end if;

  -- Same lock as check_in_player(): every room row for the event, held for
  -- the whole operation, so this cannot race a player's own concurrent
  -- check-in (which takes the identical lock) into overfilling a room.
  for v_reg in
    select er.* from event_registrations er
     where er.event_id = v_event.id and er.checked_in_at is not null
       and not exists (select 1 from room_memberships rm where rm.registration_id = er.id and rm.left_at is null)
     order by er.checked_in_at
  loop
    v_membership_id := null;

    for v_room in
      select ro.* from rooms ro where ro.event_id = v_event.id order by ro.position for update
    loop
      if v_room.capacity is null then
        continue;
      end if;

      v_reserved := case when exists (
        select 1 from room_coordinators rc
         where rc.room_id = v_room.id and rc.replaced_at is null
           and not exists (
             select 1 from room_memberships rm2
              where rm2.room_id = v_room.id and rm2.registration_id = rc.registration_id and rm2.left_at is null
           )
      ) then 1 else 0 end;

      if (select count(*) from room_memberships where room_id = v_room.id and left_at is null) < (v_room.capacity - v_reserved) then
        insert into room_memberships (event_id, room_id, registration_id)
        values (v_event.id, v_room.id, v_reg.id)
        returning id into v_membership_id;
        exit;
      end if;
    end loop;

    if v_membership_id is not null then
      v_assigned := v_assigned + 1;
    else
      v_still_waiting := v_still_waiting + 1;
      -- Every remaining room is full for this pass — later waiting
      -- registrations will not find room either, so stop scanning them.
      exit;
    end if;
  end loop;

  insert into audit_logs (event_id, actor_user_id, action, entity_type, after)
  values (v_event.id, v_uid, 'room.waiting_assigned', 'events',
          jsonb_build_object('assigned', v_assigned, 'stillWaiting', v_still_waiting));

  return jsonb_build_object('assigned', v_assigned, 'stillWaiting', v_still_waiting);
end;
$$;

revoke all on function public.admin_list_rooms(text) from public;
revoke all on function public.check_in_player() from public;
revoke all on function public.admin_assign_waiting_players(text) from public;
grant execute on function public.admin_list_rooms(text) to authenticated;
grant execute on function public.check_in_player() to authenticated;
grant execute on function public.admin_assign_waiting_players(text) to authenticated;

-- ------------------------------------------------------------- admin_add_event_game

-- Signature gains p_duration_minutes. Postgres resolves overloads by full
-- parameter signature, so leaving the old 3-argument version in place
-- alongside a new 4-argument one would not "replace" it — it would create
-- real ambiguity risk and a genuine dangling old overload. The explicit
-- DROP is what a forward-only migration changing a signature looks like;
-- migration 0019 itself (already deployed) is untouched.
drop function if exists public.admin_add_event_game(text, uuid, integer);

create or replace function public.admin_add_event_game(
  p_event_slug text,
  p_game_id    uuid,
  p_position   integer,
  p_duration_minutes integer default null
) returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_uid uuid := auth.uid();
  v_event_id uuid;
  v_game record;
  v_event_game public.event_games;
begin
  perform public.require_event_admin();

  select id into v_event_id from events where slug = p_event_slug;
  if not found then
    raise exception 'event_not_found: no such event' using errcode = 'no_data_found';
  end if;

  select * into v_game from games where id = p_game_id and status = 'ACTIVE';
  if not found then
    raise exception 'game_not_found: no such game in the library' using errcode = 'no_data_found';
  end if;

  if p_position is null or p_position <= 0 then
    raise exception 'invalid_position: position must be a positive number' using errcode = '22023';
  end if;
  if p_duration_minutes is not null and p_duration_minutes <= 0 then
    raise exception 'invalid_duration: duration must be a positive number of minutes' using errcode = '22023';
  end if;

  begin
    insert into event_games (event_id, game_id, position, scoring_template, planned_rounds, duration_minutes)
    values (
      v_event_id, v_game.id, p_position, v_game.scoring_template, v_game.default_round_count,
      coalesce(p_duration_minutes, v_game.default_duration_minutes)
    )
    returning * into v_event_game;
  exception when unique_violation then
    raise exception 'game_already_added: this game is already in the event' using errcode = '23505';
  end;

  insert into audit_logs (event_id, actor_user_id, action, entity_type, entity_id, after)
  values (v_event_id, v_uid, 'event_game.added', 'event_games', v_event_game.id,
          jsonb_build_object('gameSlug', v_game.slug, 'position', p_position, 'durationMinutes', v_event_game.duration_minutes));

  return jsonb_build_object('id', v_event_game.id, 'gameSlug', v_game.slug, 'position', p_position, 'durationMinutes', v_event_game.duration_minutes);
end;
$$;

revoke all on function public.admin_add_event_game(text, uuid, integer, integer) from public;
grant execute on function public.admin_add_event_game(text, uuid, integer, integer) to authenticated;

-- ----------------------------------------------- room-game progression auth helper

-- True if auth.uid() is either staff (SUPER_ADMIN/EVENT_ADMIN) or the
-- currently active coordinator of the given room. Shared by
-- start_room_game/complete_room_game so "who may move this room's game
-- forward" is defined once. Never trusts a client-supplied room id alone —
-- every caller of this still separately confirms the room belongs to the
-- event in question.
create or replace function public.is_authorized_for_room(p_room_id uuid)
returns boolean
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
declare
  v_uid uuid := auth.uid();
begin
  if v_uid is null then
    return false;
  end if;
  if public.current_staff_role() in ('SUPER_ADMIN', 'EVENT_ADMIN') then
    return true;
  end if;
  return exists (
    select 1 from room_coordinators rc
     join event_registrations er on er.id = rc.registration_id
    where rc.room_id = p_room_id and rc.replaced_at is null and er.auth_user_id = v_uid
  );
end;
$$;

revoke all on function public.is_authorized_for_room(uuid) from public;

-- ------------------------------------------------------------- start_room_game

-- Coordinator-or-admin. Enforces: no other game LIVE in this room right
-- now, and normal progression cannot skip the configured event-game order
-- (the immediately preceding configured game, if one exists, must be
-- COMPLETE for this room). Idempotent: starting an already-LIVE game for
-- this room is a no-op returning the current row, not an error — a
-- coordinator's retried tap must not be a hard failure.
create or replace function public.start_room_game(
  p_room_id uuid,
  p_event_game_id uuid
) returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_event_id uuid;
  v_this_game record;
  v_prev_game record;
  v_prev_row record;
  v_row public.room_event_games;
begin
  select event_id into v_event_id from rooms where id = p_room_id;
  if v_event_id is null then
    raise exception 'room_not_found: no such room' using errcode = 'no_data_found';
  end if;

  if not public.is_authorized_for_room(p_room_id) then
    raise exception 'not_authorized: not this room''s coordinator or an event admin' using errcode = '42501';
  end if;

  select * into v_this_game from event_games where id = p_event_game_id and event_id = v_event_id;
  if not found then
    raise exception 'event_game_not_found: this game is not configured for this room''s event' using errcode = 'no_data_found';
  end if;

  select * into v_row from room_event_games where room_id = p_room_id and event_game_id = p_event_game_id for update;
  if found and v_row.status = 'LIVE' then
    return jsonb_build_object('roomId', p_room_id, 'eventGameId', p_event_game_id, 'status', v_row.status);
  end if;

  if exists (select 1 from room_event_games where room_id = p_room_id and status = 'LIVE') then
    raise exception 'room_game_already_live: this room already has a different game live' using errcode = '55000';
  end if;

  select * into v_prev_game from event_games
   where event_id = v_event_id and position < v_this_game.position
   order by position desc limit 1;

  if found then
    select * into v_prev_row from room_event_games
     where room_id = p_room_id and event_game_id = v_prev_game.id;
    if not found or v_prev_row.status <> 'COMPLETE' then
      raise exception 'game_order_violation: the previous configured game must be completed first for this room' using errcode = '55000';
    end if;
  end if;

  insert into room_event_games (event_id, room_id, event_game_id, status, started_at)
  values (v_event_id, p_room_id, p_event_game_id, 'LIVE', now())
  on conflict (room_id, event_game_id) do update
    set status = 'LIVE', started_at = now(), ended_at = null
  returning * into v_row;

  return jsonb_build_object('roomId', p_room_id, 'eventGameId', p_event_game_id, 'status', v_row.status, 'startedAt', v_row.started_at);
end;
$$;

revoke all on function public.start_room_game(uuid, uuid) from public;
grant execute on function public.start_room_game(uuid, uuid) to authenticated;

-- ----------------------------------------------------------- complete_room_game

create or replace function public.complete_room_game(
  p_room_id uuid,
  p_event_game_id uuid
) returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_row public.room_event_games;
begin
  if not public.is_authorized_for_room(p_room_id) then
    raise exception 'not_authorized: not this room''s coordinator or an event admin' using errcode = '42501';
  end if;

  select * into v_row from room_event_games
   where room_id = p_room_id and event_game_id = p_event_game_id for update;

  if not found then
    raise exception 'room_game_not_found: this room has not started this game' using errcode = 'no_data_found';
  end if;

  if v_row.status = 'COMPLETE' then
    return jsonb_build_object('roomId', p_room_id, 'eventGameId', p_event_game_id, 'status', v_row.status);
  end if;
  if v_row.status <> 'LIVE' then
    raise exception 'room_game_not_live: this room''s game is not currently live' using errcode = '55000';
  end if;

  update room_event_games
     set status = 'COMPLETE', ended_at = now()
   where id = v_row.id
   returning * into v_row;

  return jsonb_build_object('roomId', p_room_id, 'eventGameId', p_event_game_id, 'status', v_row.status, 'endedAt', v_row.ended_at);
end;
$$;

revoke all on function public.complete_room_game(uuid, uuid) from public;
grant execute on function public.complete_room_game(uuid, uuid) to authenticated;
