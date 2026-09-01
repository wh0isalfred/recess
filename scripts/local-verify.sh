#!/usr/bin/env bash
# RECESS — local Phase 1 verification.
#
# Preferred path is the Supabase CLI (see README). This script exists for
# environments without Docker: it applies the same migrations, in the same
# filename order, to a plain PostgreSQL 17 instance, after installing the
# Supabase-provided objects our migrations depend on (scripts/harness).
#
#   PGURL=postgres://... scripts/local-verify.sh
set -euo pipefail

PSQL="${PSQL:-psql}"
PGURL="${PGURL:?set PGURL to a superuser connection string}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
RUN="${1:-run}"

q() { $PSQL "$PGURL" -v ON_ERROR_STOP=1 -q "$@"; }

echo "== reset: dropping and recreating public/auth =="
q -c "drop schema if exists public cascade;
      drop schema if exists auth cascade;
      drop schema if exists extensions cascade;
      create schema public;"

echo "== harness: Supabase-provided objects =="
q -f "$ROOT/scripts/harness/00_supabase_shim.sql"

echo "== migrations =="
for f in "$ROOT"/supabase/migrations/*.sql; do
  printf '   %s\n' "$(basename "$f")"
  q -f "$f"
done

echo "== seed =="
q -f "$ROOT/supabase/seed.sql"

echo "== digest (tests 1 and 17: reset reproducibility) =="
DIGEST_DIR="${DIGEST_DIR:-/tmp/recess-verify}"
mkdir -p "$DIGEST_DIR"
"${PG_DUMP:-pg_dump}" "$PGURL" --schema-only --schema=public --no-owner --no-privileges \
  | grep -v '^--' | grep -v '^$' | grep -v '^.restrict ' | grep -v '^.unrestrict ' > "$DIGEST_DIR/schema.$RUN.sql"
$PSQL "$PGURL" -tAF'|' -c "
  select 'games', count(*) from public.games
  union all select 'events', count(*) from public.events
  union all select 'event_games', count(*) from public.event_games
  union all select 'rooms', count(*) from public.rooms
  union all select 'event_counters', count(*) from public.event_counters
  order by 1" > "$DIGEST_DIR/seed.$RUN.txt"
$PSQL "$PGURL" -tA -c \
  "select md5(string_agg(g.slug || g.default_scoring_config::text, '|' order by g.slug))
     from public.games g" >> "$DIGEST_DIR/seed.$RUN.txt"

echo "== tests =="
fail=0
for f in "$ROOT"/supabase/tests/*.test.sql; do
  printf '\n-- %s\n' "$(basename "$f")"
  if ! $PSQL "$PGURL" -v ON_ERROR_STOP=1 -q -f "$f"; then
    fail=1
  fi
done

exit $fail
