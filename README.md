# audit_logs / DRAFT-event-delete fix — files

## Where each file goes

```
supabase/migrations/20260901002200_audit_log_event_delete_fix.sql   (new)
supabase/tests/15_audit_log_event_delete_fix.test.sql               (new)
```

Both are new files — no existing file is modified, no migration 0001–0021 is edited.

## What's in the migration

- A dedicated `audit_logs`-only trigger function replacing the shared
  `refuse_update()` on that one table (verified `audit_logs` was its only
  user — zero effect on any other append-only table). It permits exactly
  one update shape: `event_id` going from a real value to `null` with every
  other column unchanged — the FK's own `ON DELETE SET NULL` action, and
  nothing else.
- `admin_delete_event(p_event_slug)` — DRAFT-only, staff-admin-authorized,
  audits the deletion itself before removing the row.

## Results

Full pgTAP suite: **336/336 pass, 0 failures** (320 pre-existing + 16 new).
TypeScript, ESLint, and production build all clean. No old migration
edited. No secrets included.

## Apply

Run migrations in order as usual (`0022` is next after `0021`); the test
file follows the existing numbered convention (`15`, after `14`).
