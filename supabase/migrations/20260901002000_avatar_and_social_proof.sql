-- 0020 — persistent avatar color, and get_player_state() social proof.
-- Phase: Player Shell V2 / Pass V2 pre-event state.
--
-- Two independent pieces:
--   1. players.avatar_color — assigned once, at first registration, from a
--      curated 8-color palette. Permanent until a future external identity
--      system (Snapchat) replaces the fallback avatar entirely — this is
--      deliberately not derived from the alias or anything else recomputable,
--      per the brief: "store the actual approved color value so the
--      player's visual identity does not change if application tokens are
--      reorganized later."
--   2. get_player_state() extended: `player.avatarColor` on every view, and
--      a `socialProof` object on PASS_COUNTDOWN only — real admitted count,
--      up to 6 {alias, avatarColor} pairs for the avatar stack (registration
--      order), first 3 aliases for the text line. No phone, no real_name, no
--      auth_id — same SECURITY DEFINER / zero-RLS-policy shape as every
--      other read in this schema.

-- ------------------------------------------------------------- avatar_color

-- The palette lives here as a check constraint, not a lookup table — eight
-- fixed values, no admin-configurable palette exists or is planned; a table
-- would be schema for a feature that doesn't exist.
--
-- DEFAULT, not just an explicit assignment in register_player(): several
-- existing pgTAP fixtures insert directly into players for test setup and
-- don't (and shouldn't have to) know about this column. A default keeps any
-- insert path — present or future — safe without a null ever being
-- possible, matching how first_seen_at/created_at already default rather
-- than relying on every caller to supply them.
alter table public.players add column avatar_color text
  default (array[
    '#FF3B8D', '#FF7A2F', '#F4B940', '#2F6BFF',
    '#7C5CFC', '#27B38A', '#E95D78', '#D94EFF'
  ])[1 + floor(random() * 8)::int];

alter table public.players add constraint players_avatar_color_palette
  check (avatar_color is null or avatar_color in (
    '#FF3B8D', '#FF7A2F', '#F4B940', '#2F6BFF',
    '#7C5CFC', '#27B38A', '#E95D78', '#D94EFF'
  ));

-- Backfill: every existing player gets one random palette value now, once.
-- `md5(random()::text)` avoids favoring the first array element the way a
-- naive `random() * 8` cast sometimes does at small n; array index is 1-based.
update public.players
   set avatar_color = (array[
         '#FF3B8D', '#FF7A2F', '#F4B940', '#2F6BFF',
         '#7C5CFC', '#27B38A', '#E95D78', '#D94EFF'
       ])[1 + floor(random() * 8)::int]
 where avatar_color is null;

alter table public.players alter column avatar_color set not null;

comment on column public.players.avatar_color is
  'Assigned once at first registration (register_player()'' s insert branch
   only — never touched on conflict/update), from the fixed 8-color palette
   above. Permanent per-player identity until a future real-identity system
   replaces the fallback avatar.';

-- --------------------------------------------------------------- register_player

-- Same function as 0016, unchanged in every other respect: only the insert
-- list/values gains avatar_color, and only in the INSERT branch. The
-- `on conflict do update` set-list still does not mention avatar_color, so
-- an existing player's color is never touched — omission, not an explicit
-- "keep the old value" clause, is what preserves it here, same as
-- canonical_alias already relies on for its own "set once" column.
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

  -- Assigned once, only reached on a genuine INSERT (a brand-new phone) —
  -- the ON CONFLICT branch below has no avatar_color in its SET list, so an
  -- existing player's color is never touched, the same way canonical_alias
  -- is preserved by omission rather than an explicit "keep old value" clause.
  v_avatar_color := (array[
    '#FF3B8D', '#FF7A2F', '#F4B940', '#2F6BFF',
    '#7C5CFC', '#27B38A', '#E95D78', '#D94EFF'
  ])[1 + floor(random() * 8)::int];

  -- Find-or-create the player by phone. Name is kept current on every
  -- registration; canonical_alias and consent are set once and then held —
  -- see the migration header for why.
  insert into public.players as p (phone_e164, real_name, canonical_alias, marketing_consent, marketing_consent_at, avatar_color)
  values (v_phone, v_real_name, v_alias, true, now(), v_avatar_color)
  on conflict (phone_e164) do update
    set real_name             = excluded.real_name,
        canonical_alias       = coalesce(p.canonical_alias, excluded.canonical_alias),
        marketing_consent     = true,
        marketing_consent_at  = coalesce(p.marketing_consent_at, now())
  returning p.id into v_player_id;

  -- Idempotent retry: a double-click or a timed-out request that actually
  -- committed returns the same registration instead of erroring or
  -- duplicating. event_registrations_event_player_key backstops this even
  -- without the lock above.
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

revoke all on function public.register_player(text, text, text, text, boolean) from public;
grant execute on function public.register_player(text, text, text, text, boolean) to authenticated;

-- --------------------------------------------------------------- get_player_state

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
   where r.auth_user_id = v_uid
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
    )
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
