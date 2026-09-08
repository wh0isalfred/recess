import type { Metadata } from "next";
import { fetchEventGames, fetchEventOverview } from "@/features/admin/actions";
import { EventTabs } from "../EventTabs";
import { ManageEventView } from "./ManageEventView";

export const metadata: Metadata = { title: "Manage event — RECESS Admin" };

export default async function ManageEventPage({ params }: { params: Promise<{ slug: string }> }) {
  const { slug } = await params;
  const [overviewResult, gamesResult] = await Promise.all([fetchEventOverview(slug), fetchEventGames(slug)]);

  if (!overviewResult.ok) {
    return (
      <main className="rc-admin-page">
        <p className="rc-admin-error">{overviewResult.message}</p>
      </main>
    );
  }

  return (
    <>
      <EventTabs slug={slug} active="manage" />
      <ManageEventView
        slug={slug}
        event={overviewResult.data.event}
        registeredCount={overviewResult.data.counts.registered}
        checkedInCount={overviewResult.data.counts.checkedIn}
        games={gamesResult.ok ? gamesResult.data : []}
      />
    </>
  );
}
