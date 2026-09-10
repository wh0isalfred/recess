import type { ReactNode } from "react";
import { redirect } from "next/navigation";
import { resolvePlayerIdentity } from "@/features/pass/actions";
import { IdentityCheckFailed } from "@/components/shared/IdentityCheckFailed";
import { PlayerShell } from "@/features/player-shell/PlayerShell";

/**
 * Phase 8.2 — the shared registered-player layout. Everything under
 * /pass, /games, /players, /more mounts through this one file, which is
 * what actually makes the bottom nav persistent across navigation between
 * them: a Next.js layout stays mounted across sibling route changes,
 * where a per-page wrapper (the previous architecture) gets torn down and
 * rebuilt on every navigation, since it lives inside the page being
 * swapped rather than the boundary around it.
 *
 * The identity guard runs once, here. resolvePlayerIdentity() is wrapped
 * in React's cache() (features/pass/actions.ts), so a page that needs the
 * full resolved state for its own purposes (only /pass does — see its own
 * page.tsx) can safely call it again without a second RPC round-trip in
 * the same request; this is what "centralize where the layout can safely
 * do so, without forcing every child to duplicate the call" means in
 * practice for a Server Component tree, where there's no prop-drilling
 * path from a layout down into an arbitrary page.
 *
 * PlayerShell now wraps every state reachable under this group, including
 * /pass's own non-PASS_COUNTDOWN states (WAITLISTED, CHECK_IN_OPEN,
 * ROOM_ASSIGNED, CHECKED_IN_WAITING) — previously nav-less, full-bleed
 * night-ground screens. This is a real, visible consequence of building
 * genuinely persistent navigation, not an oversight: PlayerShell.tsx's own
 * comment already called this "only PASS_COUNTDOWN uses it this slice,"
 * naming the eventual "every registered-player screen" state as the
 * intended direction — this phase is what makes that structural. Each
 * screen's own Surface still sets its own ground/background exactly as
 * before; the one visible change is the bottom nav bar (position: fixed,
 * paper background) now appearing over those screens too, where
 * previously there was none. Flagged prominently in the delivery report.
 */
export default async function PlayerLayout({ children }: { children: ReactNode }) {
  const identity = await resolvePlayerIdentity();

  if (identity.status === "unregistered") redirect("/register");
  if (identity.status === "unknown") return <IdentityCheckFailed />;

  return <PlayerShell>{children}</PlayerShell>;
}
