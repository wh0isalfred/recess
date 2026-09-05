import type { ReactNode } from "react";
import { PlayerShellNav } from "./PlayerShellNav";

/**
 * The registered-player foundation: a bounded mobile-app canvas (desktop
 * doesn't stretch to 1440px — it centers the same phone-shaped composition,
 * per the brief), safe-area padding, and the persistent bottom nav with
 * enough content padding that nothing hides behind it.
 *
 * Applied to PASS_COUNTDOWN only in this slice — WAITLISTED/CHECK_IN_OPEN/
 * ROOM_ASSIGNED/CHECKED_IN_WAITING keep their existing presentation
 * unchanged (see the delivery report for why retrofitting nav onto
 * explicitly out-of-scope screens was deliberately not done here).
 */
export function PlayerShell({
  active,
  children,
}: {
  active: "pass" | "games" | "players" | "more";
  children: ReactNode;
}) {
  return (
    <div className="rc-shell">
      <div className="rc-shell-canvas">{children}</div>
      <PlayerShellNav active={active} />
    </div>
  );
}
