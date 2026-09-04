import type { Metadata } from "next";
import Link from "next/link";
import { fetchEventsList } from "@/features/admin/actions";
import { formatEventDate, formatEventTime } from "@/features/registration/calendar";

export const metadata: Metadata = { title: "Events — RECESS Admin" };

const STATUS_TONE: Record<string, string> = {
  DRAFT: "muted",
  REGISTRATION: "go",
  REGISTRATION_CLOSED: "warn",
  CHECK_IN: "accent",
  LIVE: "accent",
  PAUSED: "warn",
  COMPLETE: "muted",
  CANCELLED: "muted",
};

export default async function AdminEventsPage() {
  const result = await fetchEventsList();

  if (!result.ok) {
    return (
      <main className="rc-admin-page">
        <p className="rc-admin-error">{result.message}</p>
      </main>
    );
  }

  const events = result.data;

  return (
    <main className="rc-admin-page">
      <header className="rc-admin-header">
        <h1 className="rc-admin-title">EVENTS</h1>
        <Link href="/admin/events/new" className="rc-admin-add-room">+ NEW EVENT</Link>
      </header>

      {events.length === 0 ? (
        <p className="rc-admin-empty">
          No events yet. Create one with NEW EVENT — nothing is seeded automatically.
        </p>
      ) : (
        <div className="rc-admin-room-list">
          {events.map((event) => (
            <Link key={event.slug} href={`/admin/events/${event.slug}/overview`} className="rc-admin-event-row">
              <div className="rc-admin-room-card">
                <div className="rc-admin-room-card-top">
                  <span className="rc-admin-room-dot" aria-hidden="true" />
                  <span className="rc-admin-room-card-label">{event.name}</span>
                  <span className={`rc-admin-status-pill rc-admin-tone-${STATUS_TONE[event.status] ?? "muted"}`}>
                    {event.status.replace("_", " ")}
                  </span>
                </div>
                <div className="rc-admin-room-card-meta">
                  <span>
                    {formatEventDate(event.startsAt, event.timezone)} ·{" "}
                    {formatEventTime(event.startsAt, event.timezone)} {event.timezoneLabel}
                  </span>
                  <span className="rc-admin-room-coordinator">{event.registeredCount} registered</span>
                </div>
              </div>
            </Link>
          ))}
        </div>
      )}
    </main>
  );
}
