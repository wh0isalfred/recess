import type { Metadata } from "next";
import { fetchRoomsOverview } from "@/features/admin/actions";
import { RoomsClient } from "./RoomsClient";

export const metadata: Metadata = { title: "Rooms — RECESS Admin" };

export default async function AdminRoomsPage() {
  const result = await fetchRoomsOverview();

  if (!result.ok) {
    return (
      <main className="rc-admin-page">
        <p className="rc-admin-error">{result.message}</p>
      </main>
    );
  }

  return <RoomsClient initial={result.data} />;
}
