-- 0015 — WhatsApp group invite URLs. Phase 1 follow-up amendment.
--
-- Adds rooms.whatsapp_group_url and tightens validation on both it and the
-- existing events.whatsapp_group_url from "any https URL" to "a WhatsApp
-- group invite URL".
--
-- Forward-only: migration 0004 is deployed and is not edited. The old event
-- constraint is dropped and replaced here.
--
-- Communication flow this supports:
--   registration -> main event group (events.whatsapp_group_url)
--   check-in -> room assignment -> that room's group (rooms.whatsapp_group_url)
-- RECESS stores and later reveals the link. It manages no memberships and
-- talks to no WhatsApp API.

-- Shared so the two columns can never drift apart. IMMUTABLE because a CHECK
-- constraint requires it.
create or replace function public.is_whatsapp_group_url(p_url text)
returns boolean language sql immutable as $$
  -- https://chat.whatsapp.com/<code> and the older /invite/<code> form.
  -- Anchored at both ends, so a lookalike host such as
  -- https://chat.whatsapp.com.example.com/AbC is rejected.
  select p_url ~ '^https://chat\.whatsapp\.com/(invite/)?[A-Za-z0-9_-]{6,64}$';
$$;

-- events: replace the loose https check. Nullable, so NULL stays valid.
alter table public.events drop constraint events_whatsapp_url_https;

alter table public.events add constraint events_whatsapp_group_url
  check (whatsapp_group_url is null or public.is_whatsapp_group_url(whatsapp_group_url));

-- rooms: the per-room group. Nullable while configuring an event.
--
-- Deliberately NOT a precondition of entering CHECK_IN. A room with no link
-- still functions: the coordinator pastes it into the main group. Room
-- capacity is different, because sequential fill genuinely cannot run without
-- it. A missing room link is a Phase 9 operational readiness warning, not a
-- state machine failure.
alter table public.rooms add column whatsapp_group_url text;

alter table public.rooms add constraint rooms_whatsapp_group_url
  check (whatsapp_group_url is null or public.is_whatsapp_group_url(whatsapp_group_url));
