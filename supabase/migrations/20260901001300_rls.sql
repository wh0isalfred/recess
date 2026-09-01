-- 0013 — row level security baseline. Gate A revision 3, §7.
--
-- RLS is enabled on every table with ZERO policies. Not one row is readable or
-- writable by anon or authenticated. All Phase 1 verification runs as
-- service_role, which bypasses RLS.
--
-- This is deliberate. Phase 3 is the first phase with a legitimate public read
-- and will add exactly the policy it can justify. Writing permissive policies
-- now, before any consumer exists, is how a schema ends up with a policy
-- nobody can justify and nobody dares remove.
--
-- The grants below are what make RLS the enforcer rather than table
-- privileges. With RLS on and no policies they confer nothing, and they keep
-- behaviour identical regardless of the project's auto-expose setting: a
-- SELECT returns zero rows rather than a privilege error.

alter table public.players                 enable row level security;
alter table public.staff_profiles          enable row level security;
alter table public.events                  enable row level security;
alter table public.event_counters          enable row level security;
alter table public.event_registrations     enable row level security;
alter table public.games                   enable row level security;
alter table public.event_games             enable row level security;
alter table public.rooms                   enable row level security;
alter table public.room_memberships        enable row level security;
alter table public.coordinator_assignments enable row level security;
alter table public.rounds                  enable row level security;
alter table public.round_participants      enable row level security;
alter table public.results                 enable row level security;
alter table public.point_transactions      enable row level security;
alter table public.awards                  enable row level security;
alter table public.award_recipients        enable row level security;
alter table public.audit_logs              enable row level security;

grant select, insert, update, delete on all tables in schema public
  to anon, authenticated, service_role;
