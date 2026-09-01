import { Panel } from "./Surface";
import { StatusBadge } from "./StatusBadge";

export type RoomState = "filling" | "full" | "live" | "empty";

/**
 * A room, seen three ways: by the player at reveal, by the coordinator as
 * their assignment, and by the admin as one tile in the rooms grid.
 *
 * Occupancy is shown as a fraction and a bar because sequential fill makes
 * "how close is this room to full" the number that actually matters on the
 * night. A missing WhatsApp link is a readiness warning here, never a blocker.
 */
export function RoomCard({
  label,
  occupied,
  capacity,
  coordinator,
  state = "filling",
  hasWhatsApp = true,
  emphasis = false,
}: {
  label: string;
  occupied: number;
  capacity: number;
  coordinator?: string;
  state?: RoomState;
  hasWhatsApp?: boolean;
  /** The player's own room. One per screen at most. */
  emphasis?: boolean;
}) {
  const pct = capacity > 0 ? Math.min(100, Math.round((occupied / capacity) * 100)) : 0;

  return (
    <Panel className={`p-5 ${emphasis ? "border-accent bg-accent-wash" : ""}`}>
      <div className="flex items-start justify-between gap-3">
        <h3 className={`font-display ${emphasis ? "text-rc-xl text-accent-text" : "text-rc-lg"}`}>
          {label}
        </h3>
        {state === "live" ? (
          <StatusBadge tone="live" pulse>
            Live
          </StatusBadge>
        ) : state === "full" ? (
          <StatusBadge tone="confirmed">Full</StatusBadge>
        ) : state === "empty" ? (
          <StatusBadge tone="inactive">Empty</StatusBadge>
        ) : (
          <StatusBadge tone="info">Filling</StatusBadge>
        )}
      </div>

      <p className="rc-numeric mt-3 text-rc-sm text-fg-soft">
        {occupied} of {capacity} players
      </p>
      <div className="mt-2 h-1.5 w-full overflow-hidden rounded-pill bg-fg-muted">
        <div
          className="h-full rounded-pill bg-accent transition-[width] duration-[var(--t-state)]"
          style={{ width: `${pct}%` }}
        />
      </div>

      <div className="mt-4 flex flex-wrap items-center gap-x-4 gap-y-1 text-rc-sm text-fg-soft">
        <span>{coordinator ? `Captain ${coordinator}` : "No captain yet"}</span>
        {!hasWhatsApp ? (
          <span className="flex items-center gap-1.5 text-warn">
            <span aria-hidden="true">◷</span> No WhatsApp link
          </span>
        ) : null}
      </div>
    </Panel>
  );
}
