-- 0011 — audit log. Gate A revision 3, §2.17.
--
-- event_id is SET NULL, not CASCADE: an audit log that disappears with the
-- thing it audits is not an audit log.

create table public.audit_logs (
  id                    uuid primary key default gen_random_uuid(),
  event_id              uuid references public.events (id) on delete set null,
  actor_user_id         uuid references auth.users (id) on delete set null,
  actor_registration_id uuid references public.event_registrations (id) on delete set null,
  action                text not null,
  entity_type           text not null,
  entity_id             uuid,
  before                jsonb,
  after                 jsonb,
  created_at            timestamptz not null default now(),

  constraint audit_logs_action_format check (action ~ '^[a-z][a-z0-9_.]{2,63}$'),
  constraint audit_logs_entity_type_length check (length(entity_type) between 1 and 63)
);

create index audit_logs_event_idx on public.audit_logs (event_id, created_at desc);

create trigger audit_logs_refuse_update
  before update on public.audit_logs
  for each row execute function public.refuse_update();

create trigger audit_logs_refuse_delete
  before delete on public.audit_logs
  for each row execute function public.refuse_delete();
