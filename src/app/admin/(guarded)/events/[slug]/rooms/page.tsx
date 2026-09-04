import type { Metadata } from "next";
import { fetchRoomsOverview } from "@/features/admin/actions";
import { EventTabs } from "../EventTabs";
import { RoomsClient } from "./RoomsClient";

export const metadata: Metadata = { title: "Rooms — RECESS Admin" };

export default async function AdminRoomsPage({ params }: { params: Promise<{ slug: string }> }) {
  const { slug } = await params;
  const result = await fetchRoomsOverview(slug);

  if (!result.ok) {
    return (
      <main className="rc-admin-page">
        <p className="rc-admin-error">{result.message}</p>
      </main>
    );
  }

  return (
    <>
      <EventTabs slug={slug} active="rooms" />
      <RoomsClient slug={slug} initial={result.data} />
    </>
  );
}
