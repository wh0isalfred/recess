import type { ReactNode } from "react";
import { PlayerShellNav } from "./PlayerShellNav";

/**
 * The registered-player foundation: a bounded mobile-app canvas (desktop
 * doesn't stretch to 1440px — it centers the same phone-shaped composition,
 * per the brief), safe-area padding, and the persistent bottom nav with
 * enough content padding that nothing hides behind it.
 *
 * Phase 8.2: rendered once, by the shared (player)/layout.tsx, instead of
 * per-page — this is what makes it (and PlayerShellNav) genuinely persist
 * across navigation rather than remount on every route change. No longer
 * takes an `active` prop: PlayerShellNav now derives the active tab from
 * the current pathname itself, since a single shared instance has no
 * per-page prop to receive it from in the first place.
 */
export function PlayerShell({ children }: { children: ReactNode }) {
  return (
    <div className="rc-shell">
      <div className="rc-shell-canvas">{children}</div>
      <PlayerShellNav />
    </div>
  );
}
