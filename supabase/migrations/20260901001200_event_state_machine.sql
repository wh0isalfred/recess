-- 0012 — the event state machine. Gate A revision 3, §4.
--
-- Status changes only through transition_event(). A guard trigger refuses any
-- other UPDATE to events.status, including from the most privileged caller,
-- because without it the transition matrix is advisory.
--
-- Role authorization (who may initiate which transition) is deliberately NOT
-- implemented here. §4 defines it as intent for Phases 8-9; Phase 1 defines
-- the domain contract only.

create or replace function public.events_status_guard()
returns trigger language plpgsql as $$
begin
  if new.status is distinct from old.status
     and coalesce(current_setting('recess.allow_status_change', true), '0') <> '1'
  then
    raise exception 'events.status may only be changed by transition_event()'
      using errcode = 'restrict_violation';
  end if;
  return new;
end;
$$;

create trigger events_guard_status
  before update on public.events
  for each row execute function public.events_status_guard();

-- Legal transitions. §4 matrix.
create or replace function public.event_transition_is_legal(
  p_from public.event_status,
  p_to   public.event_status
) returns boolean language sql immutable as $$
  select (p_from, p_to) in (
    ('DRAFT',              'REGISTRATION'),
    ('DRAFT',              'CANCELLED'),
    ('REGISTRATION',       'DRAFT'),
    ('REGISTRATION',       'REGISTRATION_CLOSED'),
    ('REGISTRATION',       'CHECK_IN'),
    ('REGISTRATION',       'CANCELLED'),
    ('REGISTRATION_CLOSED','REGISTRATION'),
    ('REGISTRATION_CLOSED','CHECK_IN'),
    ('REGISTRATION_CLOSED','CANCELLED'),
    ('CHECK_IN',           'REGISTRATION'),
    ('CHECK_IN',           'REGISTRATION_CLOSED'),
    ('CHECK_IN',           'LIVE'),
    ('CHECK_IN',           'CANCELLED'),
    ('LIVE',               'CHECK_IN'),
    ('LIVE',               'PAUSED'),
    ('LIVE',               'COMPLETE'),
    ('LIVE',               'CANCELLED'),
    ('PAUSED',             'LIVE'),
    ('PAUSED',             'COMPLETE'),
    ('PAUSED',             'CANCELLED'),
    ('COMPLETE',           'LIVE')
  );
$$;

create or replace function public.transition_event(
  p_event_id uuid,
  p_to       public.event_status,
  p_reason   text default null
) returns public.events
language plpgsql security definer set search_path = public, pg_temp as $$
declare
  v_event  public.events;
  v_from   public.event_status;
  v_offend text;
begin
  select * into v_event from public.events where id = p_event_id for update;
  if not found then
    raise exception 'event % does not exist', p_event_id using errcode = 'no_data_found';
  end if;

  v_from := v_event.status;

  -- Idempotent no-op: returns unchanged and writes no audit row. §4 mechanics.
  if v_from = p_to then
    return v_event;
  end if;

  if not public.event_transition_is_legal(v_from, p_to) then
    raise exception 'illegal transition % -> % for event %', v_from, p_to, v_event.slug
      using errcode = 'check_violation';
  end if;

  -- ---------------------------------------------------------- preconditions

  if p_to = 'REGISTRATION' and v_from = 'DRAFT' then
    if v_event.registration_opens_at is null or v_event.registration_closes_at is null then
      raise exception 'cannot open registration: registration window is not set'
        using errcode = 'check_violation';
    end if;
    if not exists (select 1 from public.event_games where event_id = p_event_id) then
      raise exception 'cannot open registration: event has no games'
        using errcode = 'check_violation';
    end if;
  end if;

  if p_to = 'DRAFT' then
    if exists (
      select 1 from public.event_registrations
      where event_id = p_event_id and status <> 'CANCELLED'
    ) then
      raise exception 'cannot return to draft: event has registrations'
        using errcode = 'check_violation';
    end if;
  end if;

  if p_to = 'REGISTRATION_CLOSED' then
    if v_event.registration_closes_at is null or now() < v_event.registration_closes_at then
      raise exception 'cannot close registration: the window is still open (move registration_closes_at first)'
        using errcode = 'check_violation';
    end if;
    if v_from = 'CHECK_IN' and exists (
      select 1 from public.event_registrations
      where event_id = p_event_id and checked_in_at is not null
    ) then
      raise exception 'cannot leave check-in: players have already checked in'
        using errcode = 'check_violation';
    end if;
  end if;

  if p_to = 'REGISTRATION' and v_from in ('REGISTRATION_CLOSED', 'CHECK_IN') then
    if now() >= v_event.starts_at then
      raise exception 'cannot reopen registration: the event has already started'
        using errcode = 'check_violation';
    end if;
    if v_event.registration_closes_at is null or v_event.registration_closes_at <= now() then
      raise exception 'cannot reopen registration: extend registration_closes_at first'
        using errcode = 'check_violation';
    end if;
    if v_from = 'CHECK_IN' and exists (
      select 1 from public.event_registrations
      where event_id = p_event_id and checked_in_at is not null
    ) then
      raise exception 'cannot leave check-in: players have already checked in'
        using errcode = 'check_violation';
    end if;
  end if;

  if p_to = 'CHECK_IN' and v_from in ('REGISTRATION', 'REGISTRATION_CLOSED') then
    if v_event.checkin_opens_at is null or v_event.checkin_closes_at is null then
      raise exception 'cannot open check-in: check-in window is not set'
        using errcode = 'check_violation';
    end if;
    if not exists (select 1 from public.rooms where event_id = p_event_id) then
      raise exception 'cannot open check-in: event has no rooms'
        using errcode = 'check_violation';
    end if;
    -- [r3] An incomplete room configuration must block check-in: sequential
    -- fill cannot fill a room with no bound. §4, §5.30.
    select string_agg(label, ', ' order by position) into v_offend
      from public.rooms
     where event_id = p_event_id and (capacity is null or capacity <= 0);
    if v_offend is not null then
      raise exception 'cannot open check-in: room(s) % have no capacity configured', v_offend
        using errcode = 'check_violation';
    end if;
    if exists (
      select 1 from public.event_games
      where event_id = p_event_id and scoring_config = '{}'::jsonb
    ) then
      raise exception 'cannot open check-in: a game has no scoring configuration'
        using errcode = 'check_violation';
    end if;
  end if;

  if p_to = 'LIVE' and v_from = 'CHECK_IN' then
    if not exists (
      select 1 from public.event_registrations
      where event_id = p_event_id and checked_in_at is not null
    ) then
      raise exception 'cannot go live: nobody has checked in'
        using errcode = 'check_violation';
    end if;
  end if;

  if p_to = 'CHECK_IN' and v_from = 'LIVE' then
    if exists (
      select 1 from public.rounds r
      join public.event_games eg on eg.id = r.event_game_id
      where eg.event_id = p_event_id
    ) then
      raise exception 'cannot return to check-in: rounds already exist'
        using errcode = 'check_violation';
    end if;
  end if;

  if p_to = 'COMPLETE' then
    if exists (
      select 1 from public.rounds r
      join public.event_games eg on eg.id = r.event_game_id
      where eg.event_id = p_event_id and r.status in ('DRAFT', 'LIVE')
    ) then
      raise exception 'cannot complete: a round is still draft or live'
        using errcode = 'check_violation';
    end if;
    if exists (
      select 1 from public.event_games
      where event_id = p_event_id and status not in ('COMPLETE', 'SKIPPED')
    ) then
      raise exception 'cannot complete: a game is neither complete nor skipped'
        using errcode = 'check_violation';
    end if;
  end if;

  -- Reopening a finished event and cancelling one both demand a reason.
  if (v_from = 'COMPLETE' and p_to = 'LIVE') or p_to = 'CANCELLED' then
    if btrim(coalesce(p_reason, '')) = '' then
      raise exception 'transition % -> % requires a reason', v_from, p_to
        using errcode = 'check_violation';
    end if;
  end if;

  -- --------------------------------------------------------------- mutation

  perform set_config('recess.allow_status_change', '1', true);

  update public.events
     set status               = p_to,
         state_version        = state_version + 1,
         results_published_at = case
           when p_to = 'COMPLETE' then now()
           when v_from = 'COMPLETE' and p_to = 'LIVE' then null
           else results_published_at
         end
   where id = p_event_id
   returning * into v_event;

  perform set_config('recess.allow_status_change', '0', true);

  insert into public.audit_logs (
    event_id, actor_user_id, action, entity_type, entity_id, before, after
  ) values (
    p_event_id,
    auth.uid(),
    'event.status_changed',
    'events',
    p_event_id,
    jsonb_build_object('status', v_from),
    jsonb_build_object('status', p_to, 'reason', p_reason)
  );

  return v_event;
end;
$$;

revoke all on function public.transition_event(uuid, public.event_status, text) from public;
