import type { Metadata } from "next";
import { fetchEventOverview } from "@/features/admin/actions";
import { EventTabs } from "../EventTabs";
import { OverviewView } from "./OverviewView";

export const metadata: Metadata = { title: "Overview — RECESS Admin" };

export default async function AdminOverviewPage({ params }: { params: Promise<{ slug: string }> }) {
  const { slug } = await params;
  const result = await fetchEventOverview(slug);

  if (!result.ok) {
    return (
      <main className="rc-admin-page">
        <p className="rc-admin-error">{result.message}</p>
      </main>
    );
  }

  return (
    <>
      <EventTabs slug={slug} active="overview" />
      <OverviewView slug={slug} data={result.data} />
    </>
  );
}
