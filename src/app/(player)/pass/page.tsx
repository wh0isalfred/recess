import type { Metadata } from "next";
import { resolvePlayerIdentity } from "@/features/pass/actions";
import { PassScreen } from "./PassScreen";

/**
 * `/pass` — the single surface a registered player's session resolves to.
 * ARCHITECTURE.md §5 names this route ahead of any screen work, and §2
 * names get_player_state() as the one function that decides what renders:
 * "the React app renders whichever view comes back, it contains no rules
 * about which screen to show." This route is that render step — the
 * decision itself lives in the database and in PassScreen's dispatch on
 * `state.view`, not here.
 *
 * Phase 8.2: the identity guard (redirect on unregistered, IdentityCheckFailed
 * on unknown) now lives once in the shared (player)/layout.tsx — by the
 * time this page renders at all, `identity.status` is already known to be
 * "registered". This call is a second, cache()-deduplicated read of the
 * same resolution (features/pass/actions.ts) rather than a second RPC
 * round-trip, needed here because this page — unlike games/players/more —
 * needs the FULL resolved state to decide which view to render, not just
 * confirmation that a registration exists.
 */
export const metadata: Metadata = {
  title: "RECESS",
};

export default async function PassPage() {
  const identity = await resolvePlayerIdentity();
  // identity.status is "registered" here — the shared layout already
  // redirected/handled every other case before this page was reached.
  if (identity.status !== "registered") return null;

  return <PassScreen state={identity.state} />;
}
