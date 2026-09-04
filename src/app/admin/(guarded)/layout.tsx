import { redirect } from "next/navigation";
import Link from "next/link";
import { getStaffSession, staffSignOut } from "@/features/admin/actions";

/**
 * The authorization boundary for every /admin/* page except /admin/login
 * itself. Not the real security boundary — that's require_event_admin()
 * inside each RPC (migration 0018), which refuses regardless of whether
 * this redirect ever ran. This is the fast, friendly front door in front of
 * it: an unauthenticated visitor never sees admin chrome at all, and every
 * page under this layout can assume `staff` is real.
 */
export default async function AdminLayout({ children }: { children: React.ReactNode }) {
  const staff = await getStaffSession();
  if (!staff) redirect("/admin/login");

  const signOut = async () => {
    "use server";
    await staffSignOut();
    redirect("/admin/login");
  };

  const NAV = [
    { href: "/admin/events", label: "Events", enabled: true },
    { href: "#", label: "Check-in", enabled: false },
    { href: "#", label: "Games", enabled: false },
    { href: "#", label: "Live Control", enabled: false },
    { href: "#", label: "Results", enabled: false },
    { href: "#", label: "Players", enabled: false },
    { href: "#", label: "Settings", enabled: false },
  ];

  return (
    <div className="rc-admin-shell">
      <aside className="rc-admin-sidebar">
        <div className="rc-admin-sidebar-mark">RECESS</div>
        <nav className="rc-admin-nav">
          {NAV.map((item) =>
            item.enabled ? (
              <Link key={item.label} href={item.href} className="rc-admin-nav-link">
                {item.label}
              </Link>
            ) : (
              <span key={item.label} className="rc-admin-nav-link rc-admin-nav-link--disabled" aria-disabled="true">
                {item.label}
              </span>
            ),
          )}
        </nav>
        <form action={signOut} className="rc-admin-sidebar-foot">
          <span className="rc-admin-staff-name">{staff.name}</span>
          <button type="submit" className="rc-admin-logout">Logout</button>
        </form>
      </aside>
      <div className="rc-admin-content">{children}</div>
    </div>
  );
}
