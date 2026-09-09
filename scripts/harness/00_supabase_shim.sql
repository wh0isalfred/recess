-- LOCAL TEST HARNESS ONLY — never runs in a real Supabase project.
--
-- Recreates the parts of a Supabase database that our migrations depend on:
-- the auth schema, the API roles, and the extensions schema. On a real
-- project all of this already exists, which is why it is not a migration.

create schema if not exists extensions;
create schema if not exists auth;

do $$ begin
  if not exists (select 1 from pg_roles where rolname = 'anon') then
    create role anon nologin noinherit;
  end if;
  if not exists (select 1 from pg_roles where rolname = 'authenticated') then
    create role authenticated nologin noinherit;
  end if;
  if not exists (select 1 from pg_roles where rolname = 'service_role') then
    create role service_role nologin noinherit bypassrls;
  end if;
end $$;

grant usage on schema public to anon, authenticated, service_role;
grant usage on schema extensions to anon, authenticated, service_role;

-- Minimal stand-in for auth.users. Only the columns our foreign keys touch,
-- plus phone/phone_confirmed_at (Phase 8.1) — real Supabase Auth populates
-- these itself once a phone OTP verification succeeds; nothing in RECESS's
-- own migrations ever writes them outside a test fixture.
create table if not exists auth.users (
  id    uuid primary key default gen_random_uuid(),
  email text,
  phone text,
  phone_confirmed_at timestamptz
);

create or replace function auth.uid() returns uuid
language sql stable as $$
  select nullif(current_setting('request.jwt.claim.sub', true), '')::uuid
$$;

grant usage on schema auth to anon, authenticated, service_role;

-- pgTAP, the approved verification harness (Gate A §11.13). Installed here
-- rather than in a migration so the test framework never reaches production.
-- `supabase test db` needs the same statement run once against the local
-- database; see README.
create extension if not exists pgtap with schema extensions;

-- Make pgtap's assertions resolvable from the test files without qualifying
-- every call, matching how `supabase test db` runs them.
do $$ begin execute format('alter database %I set search_path = public, extensions', current_database()); end $$;
