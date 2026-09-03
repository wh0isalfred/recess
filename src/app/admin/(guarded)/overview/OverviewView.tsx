import type { EventOverview } from "@/features/admin/types";
import { formatEventDate, formatEventTime } from "@/features/registration/calendar";
import { OpenCheckInButton } from "./OpenCheckInButton";

const FLOW_STEPS = ["Registration", "Check-in", "Live", "Complete"] as const;
const FLOW_INDEX: Record<string, number> = {
  DRAFT: 0,
  REGISTRATION: 0,
  REGISTRATION_CLOSED: 0,
  CHECK_IN: 1,
  LIVE: 2,
  PAUSED: 2,
  COMPLETE: 3,
  CANCELLED: 3,
};

function roomStatus(occupancy: number, capacity: number | null): { label: string; tone: string } {
  if (capacity === null) return { label: "NOT READY", tone: "warn" };
  if (occupancy >= capacity) return { label: "FULL", tone: "accent" };
  if (occupancy === 0) return { label: "READY", tone: "muted" };
  return { label: "ACTIVE", tone: "go" };
}

export function OverviewView({ data }: { data: EventOverview }) {
  const { event, counts, rooms, nextGame } = data;
  const flowIndex = FLOW_INDEX[event.status] ?? 0;

  return (
    <main className="rc-admin-page">
      <header className="rc-admin-header">
        <div>
          <h1 className="rc-admin-title">
            RECESS — {formatEventDate(event.startsAt, event.timezone).split(" \u00B7 ")[1] ?? event.name}
          </h1>
          <p className="rc-admin-subtitle">
            {formatEventDate(event.startsAt, event.timezone)} · {formatEventTime(event.startsAt, event.timezone)}{" "}
            {event.timezoneLabel}
          </p>
        </div>
        <div className="rc-admin-header-actions">
          <span className="rc-admin-status-chip">{event.status.replace("_", " ")}</span>
          <button type="button" className="rc-admin-manage-btn" disabled title="Full event settings — later phase">
            MANAGE EVENT
          </button>
        </div>
      </header>

      <section className="rc-admin-metrics">
        <div className="rc-admin-metric">
          <span className="rc-admin-metric-value rc-numeric">{counts.registered}</span>
          <span className="rc-admin-metric-label">REGISTERED</span>
        </div>
        <div className="rc-admin-metric">
          <span className="rc-admin-metric-value rc-numeric">{counts.checkedIn}</span>
          <span className="rc-admin-metric-label">CHECKED IN</span>
        </div>
        <div className="rc-admin-metric">
          <span className="rc-admin-metric-value rc-numeric">{counts.assigned}</span>
          <span className="rc-admin-metric-label">ASSIGNED</span>
        </div>
        <div className="rc-admin-metric rc-admin-metric--warn">
          <span className="rc-admin-metric-value rc-numeric">{counts.waiting}</span>
          <span className="rc-admin-metric-label">WAITING</span>
        </div>
      </section>

      <section className="rc-admin-card">
        <h2 className="rc-admin-card-title">EVENT FLOW</h2>
        <div className="rc-admin-flow">
          {FLOW_STEPS.map((label, i) => (
            <div key={label} className={`rc-admin-flow-step ${i <= flowIndex ? "rc-admin-flow-step--done" : ""}`}>
              <span className="rc-admin-flow-dot" />
              <span className="rc-admin-flow-label">{label}</span>
            </div>
          ))}
        </div>
        <OpenCheckInButton disabled={event.status !== "REGISTRATION" && event.status !== "REGISTRATION_CLOSED"} />
      </section>

      <section className="rc-admin-card">
        <div className="rc-admin-card-head">
          <h2 className="rc-admin-card-title">ROOMS</h2>
          <a href="/admin/rooms" className="rc-admin-view-all">VIEW ALL →</a>
        </div>
        <div className="rc-admin-room-grid">
          {rooms.slice(0, 3).map((room) => {
            const status = roomStatus(room.occupancy, room.capacity);
            const pct = room.capacity ? Math.min(100, (room.occupancy / room.capacity) * 100) : 0;
            return (
              <div key={room.id} className="rc-admin-room-tile">
                <span className="rc-admin-room-tile-label rc-numeric">{room.label}</span>
                <span className="rc-admin-room-tile-count rc-numeric">
                  {room.occupancy} / {room.capacity ?? "—"}
                </span>
                <span className={`rc-admin-room-tile-status rc-admin-tone-${status.tone}`}>{status.label}</span>
                <span className="rc-admin-room-tile-bar">
                  <span className="rc-admin-room-tile-bar-fill" style={{ width: `${pct}%` }} />
                </span>
              </div>
            );
          })}
          {rooms.length === 0 ? <p className="rc-admin-empty">No rooms configured yet.</p> : null}
        </div>
      </section>

      <section className="rc-admin-card rc-admin-card--next">
        <h2 className="rc-admin-card-title">NEXT</h2>
        {nextGame ? (
          <div className="rc-admin-next-row">
            <div>
              <p className="rc-admin-next-name">{nextGame.name} · Round 1</p>
              <p className="rc-admin-next-status">Not started yet</p>
            </div>
            <button type="button" className="rc-admin-live-btn" disabled title="Live Control — later phase">
              <span aria-hidden="true">▶</span> OPEN LIVE CONTROL
            </button>
          </div>
        ) : (
          <p className="rc-admin-empty">No games configured for this event yet.</p>
        )}
      </section>
    </main>
  );
}
