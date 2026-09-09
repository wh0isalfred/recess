-- 0030 — Phase 8.1: Player Access & Secure Multi-Device Recovery.
--
-- The permanent identity is players.id. An auth session (anonymous or
-- phone-verified) is only ever an IDENTITY ALLOWED TO ACT AS that player —
-- never the player itself. This migration introduces that mapping,
-- centralizes every place that used to resolve "the current player" by
-- comparing event_registrations.auth_user_id = auth.uid() directly, and
-- closes a real vulnerability in register_player() along the way (found
-- during the required audit, not assumed): its players upsert
-- unconditionally overwrote real_name for any phone number submitted,
-- authenticated session or not, which meant an unverified session could
-- silently modify an existing player's stored name merely by submitting
-- their phone number on the registration form.
--
-- event_registrations.auth_user_id itself is left alone — still set at
-- registration time, still exactly what it always was. Nothing here
-- repurposes or removes it; the new resolution path runs alongside it.

-- ============================================================ 1. TABLE

create table public.player_auth_identities (
  id           uuid primary key default gen_random_uuid(),
  player_id    uuid not null references public.players (id) on delete cascade,
  auth_user_id uuid not null,
  identity_type text not null default 'ANONYMOUS',
  verified_at  timestamptz,
  created_at   timestamptz not null default now(),

  constraint player_auth_identities_type_check check (identity_type in ('ANONYMOUS', 'PHONE_VERIFIED')),
  -- One auth session maps to exactly one player, permanently. This is the
  -- actual multi-device model: many rows can share a player_id (many
  -- devices/sessions recognized as the same player), but a given
  -- auth_user_id can never appear twice, and never against two different
  -- players — an auth session doesn't get to "become" a different player
  -- later.
  constraint player_auth_identities_auth_user_unique unique (auth_user_id),
  constraint player_auth_identities_player_auth_unique unique (player_id, auth_user_id)
);

create index player_auth_identities_player_idx on public.player_auth_identities (player_id);

alter table public.player_auth_identities enable row level security;
grant select, insert, update on public.player_auth_identities to anon, authenticated, service_role;

comment on table public.player_auth_identities is
  'Many-device identity mapping (Phase 8.1). players.id is the permanent
   identity; each row here is one auth session recognized as that player.
   ANONYMOUS rows are created automatically (see
   event_registrations_sync_identity below) whenever a registration is
   inserted with a non-null auth_user_id; PHONE_VERIFIED rows are created
   by recover_player_access() after a real Supabase phone-OTP
   verification. Neither ever deletes the other.';

-- The single centralized point that keeps player_auth_identities
-- consistent with event_registrations — a trigger rather than an explicit
-- insert inside register_player() alone, so this invariant holds
-- regardless of which code path creates a registration (register_player()
-- today; anything else later; a test fixture inserting directly). "Do not
-- scatter new auth logic across functions" applies to this exactly as
-- much as to the read side.
create or replace function public.event_registrations_sync_identity()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  if new.auth_user_id is not null then
    insert into public.player_auth_identities (player_id, auth_user_id, identity_type)
    values (new.player_id, new.auth_user_id, 'ANONYMOUS')
    on conflict (auth_user_id) do nothing;
  end if;
  return new;
end;
$$;

create trigger event_registrations_sync_identity
  after insert or update of auth_user_id on public.event_registrations
  for each row execute function public.event_registrations_sync_identity();

-- Backfill: every registration already has an auth_user_id from the
-- anonymous session that created it. event_registrations already enforces
-- (per its own partial unique index) that one auth_user_id can never
-- belong to more than one active registration, so this can never conflict
-- with the new unique(auth_user_id) constraint above.
insert into public.player_auth_identities (player_id, auth_user_id, identity_type, verified_at, created_at)
select distinct on (er.auth_user_id) er.player_id, er.auth_user_id, 'ANONYMOUS', null, er.created_at
  from public.event_registrations er
 where er.auth_user_id is not null
on conflict (auth_user_id) do nothing;

-- ============================================================ 2. current_player_id()

-- The one centralized resolver every function below now uses instead of
-- comparing event_registrations.auth_user_id = auth.uid() directly. Null
-- when the current session has no recognized identity at all (a brand
-- new anonymous session that has never registered, or a phone-verified
-- session that has never recovered access).
create or replace function public.current_player_id()
returns uuid
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select player_id from public.player_auth_identities where auth_user_id = auth.uid();
$$;

revoke all on function public.current_player_id() from public;
grant execute on function public.current_player_id() to authenticated;

-- ============================================================ 3. get_player_state()

create or replace function public.get_player_state()
returns jsonb
language plpgsql
security definer
stable
set search_path = public, pg_temp
as $$
declare
  v_uid       uuid;
  v_reg       record;
  v_membership record;
  v_view      text;
  v_checkin_available boolean;
  v_payload   jsonb;
  v_up_first  jsonb;
  v_avatar_color text;
  v_social    jsonb;
  v_coordinating jsonb;
begin
  v_uid := auth.uid();
  if v_uid is null then
    return null;
  end if;

  select r.id, r.alias, r.player_number, r.status, r.checked_in_at, r.event_id,
         e.slug as event_slug, e.name as event_name, e.status as event_status,
         e.starts_at, e.timezone, e.timezone_label, e.whatsapp_group_url,
         e.checkin_opens_at, e.checkin_closes_at, p.avatar_color
    into v_reg
    from public.event_registrations r
    join public.events e on e.id = r.event_id
    join public.players p on p.id = r.player_id
   where r.player_id = public.current_player_id()
   order by r.created_at desc
   limit 1;

  if not found then
    return null;
  end if;

  v_avatar_color := v_reg.avatar_color;

  select rm.id, rm.room_id, rm2.label as room_label, rm2.capacity as room_capacity,
         rm2.whatsapp_group_url as room_whatsapp_url
    into v_membership
    from public.room_memberships rm
    join public.rooms rm2 on rm2.id = rm.room_id
   where rm.registration_id = v_reg.id and rm.left_at is null;

  v_checkin_available :=
    (v_reg.checkin_opens_at is null or now() >= v_reg.checkin_opens_at)
    and (v_reg.checkin_closes_at is null or now() < v_reg.checkin_closes_at);

  if v_reg.status = 'CANCELLED' then
    v_view := 'CANCELLED';
  elsif v_reg.status = 'WAITLISTED' then
    v_view := 'WAITLISTED';
  elsif v_reg.event_status = 'CANCELLED' then
    v_view := 'EVENT_CANCELLED';
  elsif v_reg.event_status in ('DRAFT', 'REGISTRATION', 'REGISTRATION_CLOSED') then
    v_view := 'PASS_COUNTDOWN';
  elsif v_reg.event_status = 'CHECK_IN' then
    if v_reg.checked_in_at is null then
      v_view := 'CHECK_IN_OPEN';
    elsif v_membership.id is not null then
      v_view := 'ROOM_ASSIGNED';
    else
      v_view := 'CHECKED_IN_WAITING';
    end if;
  elsif v_reg.event_status in ('LIVE', 'PAUSED') then
    if v_reg.checked_in_at is null then
      v_view := 'MISSED_CHECK_IN';
    elsif v_membership.id is not null then
      v_view := 'ROOM_ASSIGNED';
    else
      v_view := 'CHECKED_IN_WAITING';
    end if;
  else
    v_view := 'RESULTS';
  end if;

  -- Coordinator detection: an active (replaced_at is null) room_coordinators
  -- row for this registration, regardless of `view` — a coordinator is
  -- still a normal player first (EVENT-OPS.md §1), so this is additive
  -- information, not a different view/routing decision.
  select jsonb_build_object('roomId', rc.room_id, 'roomLabel', ro.label)
    into v_coordinating
    from public.room_coordinators rc
    join public.rooms ro on ro.id = rc.room_id
   where rc.registration_id = v_reg.id and rc.replaced_at is null;

  v_payload := jsonb_build_object(
    'view', v_view,
    'event', jsonb_build_object(
      'id', v_reg.event_id,
      'slug', v_reg.event_slug,
      'name', v_reg.event_name,
      'status', v_reg.event_status,
      'startsAt', v_reg.starts_at,
      'timezone', v_reg.timezone,
      'timezoneLabel', v_reg.timezone_label,
      'whatsappGroupUrl', case when v_view = 'PASS_COUNTDOWN' then v_reg.whatsapp_group_url else null end
    ),
    'player', jsonb_build_object(
      'registrationId', v_reg.id,
      'alias', v_reg.alias,
      'number', v_reg.player_number,
      'registrationStatus', v_reg.status,
      'checkedInAt', v_reg.checked_in_at,
      'avatarColor', v_avatar_color
    ),
    'checkIn', jsonb_build_object(
      'opensAt', v_reg.checkin_opens_at,
      'closesAt', v_reg.checkin_closes_at,
      'available', v_checkin_available
    ),
    'coordinating', v_coordinating
  );

  if v_view = 'PASS_COUNTDOWN' then
    v_payload := v_payload || jsonb_build_object('games', (
      select coalesce(jsonb_agg(
               jsonb_build_object(
                 'slug', g.slug,
                 'name', coalesce(eg.display_name, g.name),
                 'platform', g.platform,
                 'artworkUrl', g.artwork_url,
                 'iconUrl', g.icon_url
               ) order by eg.position
             ), '[]'::jsonb)
        from public.event_games eg
        join public.games g on g.id = eg.game_id
       where eg.event_id = v_reg.event_id and g.status = 'ACTIVE'
    ));

    -- Social proof: admitted (REGISTERED, not WAITLISTED) players only,
    -- ordered by player_number — guaranteed strictly increasing per event
    -- (allocated under the same locked counter check_in_player() already
    -- relies on), so ordering never ties the way created_at can when two
    -- registrations land in the same transaction/millisecond. alias +
    -- avatarColor only — never player_id, registration_id, phone, or
    -- real_name. avatars capped at 6 for the stack; previewAliases capped
    -- at 3 for the "kemz, sarahh, theomz + N others" text — the client
    -- computes the remainder from admittedCount, not from array length, so
    -- it stays correct even though only 6 avatars/3 aliases ever come down
    -- the wire.
    select jsonb_build_object(
             'admittedCount', (
               select count(*) from public.event_registrations er
                where er.event_id = v_reg.event_id and er.status = 'REGISTERED'
             ),
             'avatars', coalesce((
               select jsonb_agg(jsonb_build_object('alias', x.alias, 'avatarColor', x.avatar_color))
                 from (
                   select er.alias, p.avatar_color
                     from public.event_registrations er
                     join public.players p on p.id = er.player_id
                    where er.event_id = v_reg.event_id and er.status = 'REGISTERED'
                    order by er.player_number asc
                    limit 6
                 ) x
             ), '[]'::jsonb),
             'previewAliases', coalesce((
               select jsonb_agg(x.alias)
                 from (
                   select er.alias
                     from public.event_registrations er
                    where er.event_id = v_reg.event_id and er.status = 'REGISTERED'
                    order by er.player_number asc
                    limit 3
                 ) x
             ), '[]'::jsonb)
           )
      into v_social;

    v_payload := v_payload || jsonb_build_object('socialProof', v_social);
  end if;

  if v_view = 'ROOM_ASSIGNED' then
    select jsonb_build_object(
             'slug', g.slug, 'name', g.name, 'platform', g.platform,
             'artworkUrl', g.artwork_url, 'iconUrl', g.icon_url
           )
      into v_up_first
      from public.event_games eg
      join public.games g on g.id = eg.game_id
     where eg.event_id = v_reg.event_id and g.status = 'ACTIVE'
     order by eg.position
     limit 1;

    v_payload := v_payload || jsonb_build_object(
      'room', jsonb_build_object(
        'label', v_membership.room_label,
        'capacity', v_membership.room_capacity,
        'occupancy', (
          select count(*) from public.room_memberships
           where room_id = v_membership.room_id and left_at is null
        ),
        'whatsappGroupUrl', v_membership.room_whatsapp_url,
        'roster', (
          select coalesce(jsonb_agg(jsonb_build_object('alias', er.alias) order by rm.assigned_at), '[]'::jsonb)
            from public.room_memberships rm
            join public.event_registrations er on er.id = rm.registration_id
           where rm.room_id = v_membership.room_id and rm.left_at is null
        )
      ),
      'upFirstGame', v_up_first
    );
  end if;

  return v_payload;
end;
$$;

-- ============================================================ 4. check_in_player()

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
   where r.player_id = public.current_player_id()
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

-- ============================================================ 5. is_authorized_for_room()

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
    where rc.room_id = p_room_id and rc.replaced_at is null and er.player_id = public.current_player_id()
  );
end;
$$;

-- ============================================================ 6. register_player() — vulnerability fix

create or replace function public.register_player(
  p_event_slug text,
  p_real_name  text,
  p_alias      text,
  p_phone_e164 text,
  p_consent    boolean
) returns table (
  registration_id     uuid,
  player_number        integer,
  alias                text,
  registration_status  public.registration_status,
  event_id             uuid,
  event_slug           text,
  event_name           text,
  starts_at            timestamptz,
  timezone             text,
  timezone_label       text,
  whatsapp_group_url   text
)
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_uid              uuid;
  v_event            public.events;
  v_real_name        text;
  v_alias            text;
  v_phone            text;
  v_player_id        uuid;
  v_existing_player_id uuid;
  v_caller_player_id  uuid;
  v_existing         public.event_registrations;
  v_registered_count integer;
  v_status           public.registration_status;
  v_next_no          integer;
  v_reg              public.event_registrations;
  v_avatar_color     text;
begin
  v_uid := auth.uid();
  if v_uid is null then
    raise exception 'not_authenticated: no player session'
      using errcode = '28000';
  end if;

  v_real_name := btrim(p_real_name);
  v_alias     := btrim(p_alias);
  v_phone     := btrim(p_phone_e164);

  if v_real_name = '' or length(v_real_name) > 120 then
    raise exception 'invalid_name: enter your name'
      using errcode = '22023';
  end if;

  if v_alias !~ '^[A-Za-z0-9._-]{2,24}$' then
    raise exception 'invalid_alias: 2-24 letters, numbers, dots, underscores or hyphens'
      using errcode = '22023';
  end if;

  if v_phone !~ '^\+[1-9][0-9]{6,14}$' then
    raise exception 'invalid_phone: enter a valid WhatsApp number'
      using errcode = '22023';
  end if;

  if not coalesce(p_consent, false) then
    raise exception 'consent_required: consent is required to register'
      using errcode = '22023';
  end if;

  select * into v_event from public.events where slug = p_event_slug;
  if not found then
    raise exception 'event_not_found: RECESS is not open for registration right now'
      using errcode = 'no_data_found';
  end if;

  if v_event.status <> 'REGISTRATION' then
    raise exception 'registration_not_open: registration is not open for this event'
      using errcode = '55000';
  end if;
  if v_event.registration_opens_at is not null and now() < v_event.registration_opens_at then
    raise exception 'registration_not_open: registration has not opened yet'
      using errcode = '55000';
  end if;
  if v_event.registration_closes_at is not null and now() >= v_event.registration_closes_at then
    raise exception 'registration_not_open: registration has closed'
      using errcode = '55000';
  end if;

  -- Serializes every registration for this event through one row lock. This
  -- is what makes the capacity count, the alias check and the player_number
  -- allocation below race-free together, not just individually safe.
  --
  -- Every reference below is table-qualified even where only one table is in
  -- scope: `returns table` gives this function an output variable named
  -- event_id (and player_number, alias, registration_status,
  -- registration_id), which would otherwise shadow the identically-named
  -- columns on event_counters and event_registrations — caught by test 38
  -- before this ever ran against real data.
  perform 1 from public.event_counters ec where ec.event_id = v_event.id for update;

  -- The actual fix: resolve who this phone already belongs to, and who
  -- this auth session is already recognized as, BEFORE touching players
  -- at all. An unverified session claiming someone else's phone number —
  -- the exact scenario this phase closes — never reaches the upsert
  -- below, so it can neither read nor modify that player's stored facts.
  select id into v_existing_player_id from public.players where phone_e164 = v_phone;
  v_caller_player_id := public.current_player_id();

  if v_existing_player_id is not null and v_caller_player_id is distinct from v_existing_player_id then
    -- Either a fresh/unrecognized session submitting someone else's real
    -- phone number, or a session already recognized as a DIFFERENT player
    -- attempting to also claim this one. Both are refused identically —
    -- neither is told which case applies, avoiding a phone-registered
    -- enumeration oracle.
    raise exception 'phone_already_registered: this WhatsApp number is already registered — use "Open your pass" to recover access'
      using errcode = '23505';
  end if;

  if v_existing_player_id is null and v_caller_player_id is not null then
    -- This session is already recognized as a different player and is
    -- attempting to register a second, brand-new phone under the same
    -- session — one auth session maps to exactly one player, permanently.
    raise exception 'session_already_registered: this device is already registered to a different player'
      using errcode = '23505';
  end if;

  -- Only actually used on a genuine INSERT (a brand-new phone) below — the
  -- existing-player UPDATE branch has no avatar_color in its SET list, so
  -- an existing player's color is never touched, the same way
  -- canonical_alias is preserved by omission rather than an explicit "keep
  -- old value" clause.
  v_avatar_color := (array[
    '#FF3B8D', '#FF7A2F', '#F4B940', '#2F6BFF',
    '#7C5CFC', '#27B38A', '#E95D78', '#D94EFF'
  ])[1 + floor(random() * 8)::int];

  if v_existing_player_id is not null then
    -- Recognized session, same player as before (a legitimate resubmit,
    -- or a device that already recovered access) — keep real_name/consent
    -- current for THIS player only, never anyone else's.
    v_player_id := v_existing_player_id;
    update public.players
       set real_name            = v_real_name,
           canonical_alias      = coalesce(canonical_alias, v_alias),
           marketing_consent    = true,
           marketing_consent_at = coalesce(marketing_consent_at, now())
     where id = v_player_id;
  else
    insert into public.players (phone_e164, real_name, canonical_alias, marketing_consent, marketing_consent_at, avatar_color)
    values (v_phone, v_real_name, v_alias, true, now(), v_avatar_color)
    returning id into v_player_id;
  end if;

  -- player_auth_identities is kept in sync by a trigger (below), not by an
  -- explicit insert here — see event_registrations_sync_identity for why
  -- that is the more centralized place for this to live.

  select er.* into v_existing
    from public.event_registrations er
   where er.event_id = v_event.id and er.player_id = v_player_id;

  if found then
    v_reg := v_existing;
  else
    if exists (
      select 1 from public.event_registrations er
       where er.event_id = v_event.id and lower(er.alias) = lower(v_alias)
    ) then
      raise exception 'alias_taken: that name is already taken for this event'
        using errcode = '23505';
    end if;

    select count(*) into v_registered_count
      from public.event_registrations er
     where er.event_id = v_event.id and er.status = 'REGISTERED';

    v_status := case
      when v_registered_count >= v_event.capacity then 'WAITLISTED'
      else 'REGISTERED'
    end;

    update public.event_counters ec
       set next_player_no = ec.next_player_no + 1
     where ec.event_id = v_event.id
     returning ec.next_player_no - 1 into v_next_no;

    insert into public.event_registrations (
      event_id, player_id, alias, player_number, status, auth_user_id
    ) values (
      v_event.id, v_player_id, v_alias, v_next_no, v_status, v_uid
    )
    returning * into v_reg;

    insert into public.audit_logs (
      event_id, actor_user_id, action, entity_type, entity_id, after
    ) values (
      v_event.id, v_uid, 'registration.created', 'event_registrations', v_reg.id,
      jsonb_build_object('alias', v_reg.alias, 'player_number', v_reg.player_number, 'status', v_reg.status)
    );
  end if;

  return query select
    v_reg.id, v_reg.player_number, v_reg.alias, v_reg.status,
    v_event.id, v_event.slug, v_event.name, v_event.starts_at,
    v_event.timezone, v_event.timezone_label, v_event.whatsapp_group_url;
end;
$$;

-- ============================================================ 7. recover_player_access()

-- The one narrow recovery path. Requires a REAL, already-verified Supabase
-- phone-OTP session (auth.users.phone_confirmed_at) — never a
-- client-supplied phone parameter, which is the exact thing this
-- function must never trust. Idempotent: a repeated call from the same
-- already-recognized device changes nothing and still succeeds. Never
-- deletes any other identity row — the original device keeps working.
create or replace function public.recover_player_access()
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_uid uuid := auth.uid();
  v_raw_phone text;
  v_phone text;
  v_player_id uuid;
  v_conflict_player_id uuid;
  v_event_id uuid;
begin
  if v_uid is null then
    raise exception 'not_authenticated: no session' using errcode = '28000';
  end if;

  select phone into v_raw_phone from auth.users where id = v_uid and phone_confirmed_at is not null;
  if v_raw_phone is null or btrim(v_raw_phone) = '' then
    raise exception 'phone_not_verified: this session has no verified phone number' using errcode = '28000';
  end if;

  -- Supabase Auth stores a verified phone as E.164 digits without a
  -- leading '+'; RECESS stores phone_e164 with one. Normalize once, here,
  -- rather than trusting any client-supplied formatting.
  v_phone := case when left(btrim(v_raw_phone), 1) = '+' then btrim(v_raw_phone) else '+' || btrim(v_raw_phone) end;

  select id into v_player_id from public.players where phone_e164 = v_phone;
  if v_player_id is null then
    raise exception 'player_not_found: no RECESS registration matches this phone number' using errcode = 'no_data_found';
  end if;

  select player_id into v_conflict_player_id from public.player_auth_identities where auth_user_id = v_uid;
  if v_conflict_player_id is not null and v_conflict_player_id <> v_player_id then
    -- Should not be reachable in practice (this auth_user_id would have to
    -- be a genuinely fresh phone-verified session for the flow above to
    -- apply at all), but fail loudly rather than silently doing nothing.
    raise exception 'identity_conflict: this session is already linked to a different player' using errcode = '55000';
  end if;

  insert into public.player_auth_identities (player_id, auth_user_id, identity_type, verified_at)
  values (v_player_id, v_uid, 'PHONE_VERIFIED', now())
  on conflict (auth_user_id) do update
    set verified_at = coalesce(public.player_auth_identities.verified_at, excluded.verified_at);

  select event_id into v_event_id from public.event_registrations where player_id = v_player_id order by created_at desc limit 1;

  insert into public.audit_logs (event_id, actor_user_id, action, entity_type, entity_id, after)
  values (v_event_id, v_uid, 'player.recovered_access', 'players', v_player_id,
          jsonb_build_object('authUserId', v_uid));

  return jsonb_build_object('playerId', v_player_id, 'recovered', true);
end;
$$;

revoke all on function public.recover_player_access() from public;
grant execute on function public.recover_player_access() to authenticated;
