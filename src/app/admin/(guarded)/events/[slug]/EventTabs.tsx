import Link from "next/link";

export function EventTabs({ slug, active }: { slug: string; active: "overview" | "rooms" }) {
  return (
    <div className="rc-admin-event-tabs">
      <Link href="/admin/events" className="rc-admin-event-back">← All events</Link>
      <nav className="rc-admin-event-tab-nav">
        <Link
          href={`/admin/events/${slug}/overview`}
          className={`rc-admin-event-tab ${active === "overview" ? "rc-admin-event-tab--active" : ""}`}
        >
          Overview
        </Link>
        <Link
          href={`/admin/events/${slug}/rooms`}
          className={`rc-admin-event-tab ${active === "rooms" ? "rc-admin-event-tab--active" : ""}`}
        >
          Rooms
        </Link>
      </nav>
    </div>
  );
}
