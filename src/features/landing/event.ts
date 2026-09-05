/**
 * Public event info for the unauthenticated Landing screen.
 *
 * BLOCKER — see delivery report: there is currently no way for a visitor
 * with no session at all to read real event data. `get_player_state()`
 * (0017/0018) requires an authenticated session and returns this caller's
 * own registration state, not general public event info; nothing in the
 * schema exposes a `SECURITY DEFINER` function granted to `anon` for the
 * safe subset of `events` columns (name, starts_at, timezone) a landing
 * page actually needs. Every other write/read path in this app is gated
 * the same way (RLS enabled, zero policies, gated functions only — see
 * ARCHITECTURE.md §migration 0013), so this isn't a shortcut anyone
 * skipped; the public-facing case just hasn't been built yet.
 *
 * This function is the one place that gap is isolated. It returns the same
 * values the pre-V2 landing page hardcoded (see the removed `EVENT` const
 * that used to live in page.tsx) so nothing regresses today, and it gives
 * whoever wires up the real RPC exactly one function to change — not a
 * search through the component tree for hardcoded strings.
 */
export type PublicEventInfo = {
  dateLabel: string;
  dayLabel: string;
  timeLabel: string;
  zoneLabel: string;
};

export async function getPublicEventInfo(): Promise<PublicEventInfo> {
  return {
    dateLabel: "11 SEPT 2026",
    dayLabel: "FRIDAY",
    timeLabel: "8:00 PM",
    zoneLabel: "WAT",
  };
}
