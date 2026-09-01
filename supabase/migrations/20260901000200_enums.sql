-- 0002 — enums. Gate A revision 3, §1.

create type public.staff_role as enum ('SUPER_ADMIN', 'EVENT_ADMIN', 'COORDINATOR');

create type public.event_status as enum (
  'DRAFT', 'REGISTRATION', 'REGISTRATION_CLOSED',
  'CHECK_IN', 'LIVE', 'PAUSED', 'COMPLETE', 'CANCELLED'
);

create type public.leaderboard_visibility as enum ('LIVE', 'BETWEEN_GAMES', 'HIDDEN_UNTIL_FINALE');

create type public.registration_status as enum ('REGISTERED', 'WAITLISTED', 'CANCELLED');

create type public.game_platform as enum ('BROWSER', 'INSTALL', 'NATIVE');

create type public.game_status as enum ('ACTIVE', 'ARCHIVED');

create type public.scoring_template as enum (
  'PLACEMENT', 'ROLE_OUTCOME', 'TEAM_OUTCOME', 'INDIVIDUAL_OUTCOME', 'MANUAL'
);

create type public.event_game_status as enum ('PENDING', 'LIVE', 'COMPLETE', 'SKIPPED');

create type public.round_status as enum ('DRAFT', 'LIVE', 'COMPLETE', 'VOID');

create type public.participation_state as enum ('PARTICIPATING', 'DNP');

create type public.transaction_source as enum ('RESULT', 'MANUAL_ADJUSTMENT');
