-- 0016 — atomic public registration. Phase 4.
--
-- Screens 03-05 collect name, alias and WhatsApp number; this is the write
-- path they call. It is the first legitimate anon/authenticated write this
-- schema has had — everything through 0015 is staff/service-role only, and
-- RLS (0013) is a deliberate zero-policy wall until a phase can justify a
-- policy. This phase can, but the justification is a function with its own
-- internal check, not a blanket policy: the same shape §4.2 already uses for
-- transition_event(), and the shape §6 names in advance for get_player_state().
-- A SELECT/RPC surface is easier to reason about and to revoke than a table
-- policy, and it is the one this codebase has already chosen twice.
--
-- Session model is §4.2 option A, taken verbatim: the browser calls
-- auth.signInAnonymously() before it calls register_player(), so the
-- function runs as an authenticated (anonymous) user and auth.uid() is the
-- session to attach. A null auth.uid() is refused outright.
--
-- Two decisions this migration makes that the existing docs establish the
-- shape of but do not spell out in prose — flagged here and in the chat
-- report, not left silent in the diff:
--
--  1. Consent. The registration screens require a checkbox before
--     submission, and nothing in 0001-0015 has anywhere to put the answer.
--     It is modelled on players, not event_registrations: "receive updates
--     about RECESS" is a standing communication preference tied to the
--     phone identity, not a fact about one edition. Consent only ever
--     strengthens here (the client blocks submission unless it is checked,
--     so there is no path that un-sets it), and marketing_consent_at is
--     stamped once, on the edition that first captured it.
--
--  2. Capacity. registration_status already has WAITLISTED sitting next to
--     REGISTERED, and events.capacity already exists — the enum has no
--     other reason to carry that value. A registration at or past capacity
--     is written as WAITLISTED rather than refused: the pass still gets a
--     player_number and a row, matching the "the state machine records
--     facts" line the schema uses everywhere else, rather than turning a
--     full room into a client-side wall. No supplied reference shows a
--     waitlisted variant of Screen 06 — see the report.

alter table public.players
  add column marketing_consent    boolean not null default false,
  add column marketing_consent_at timestamptz,
  add constraint players_consent_at_consistent check (
    (marketing_consent and marketing_consent_at is not null)
    or (not marketing_consent and marketing_consent_at is null)
  );

-- ---------------------------------------------------------------- register_player

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

  -- Find-or-create the player by phone. Name is kept current on every
  -- registration; canonical_alias and consent are set once and then held —
  -- see the migration header for why.
  insert into public.players as p (phone_e164, real_name, canonical_alias, marketing_consent, marketing_consent_at)
  values (v_phone, v_real_name, v_alias, true, now())
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

-- ------------------------------------------------------------- get_my_registration

-- The read Screen 06 (and its refresh) needs. Same reasoning as above: a
-- narrow function whose only filter is auth.uid() rather than an RLS policy
-- opened before a second consumer exists to justify its shape. This is
-- scoped to what Phase 4 needs; §6's get_player_state() is the later,
-- broader version once countdown/check-in/room state exists to report.

create or replace function public.get_my_registration()
returns table (
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
language sql
security definer
stable
set search_path = public, pg_temp
as $$
  select r.id, r.player_number, r.alias, r.status,
         e.id, e.slug, e.name, e.starts_at, e.timezone, e.timezone_label, e.whatsapp_group_url
    from public.event_registrations r
    join public.events e on e.id = r.event_id
   where r.auth_user_id = auth.uid()
   order by r.created_at desc
   limit 1;
$$;

revoke all on function public.get_my_registration() from public;
grant execute on function public.get_my_registration() to authenticated;
