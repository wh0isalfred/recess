import type { Metadata } from "next";
import { fetchGamesLibrary } from "@/features/admin/actions";
import { NewEventForm } from "./NewEventForm";

export const metadata: Metadata = { title: "New event — RECESS Admin" };

export default async function NewEventPage() {
  const result = await fetchGamesLibrary();

  return (
    <main className="rc-admin-page">
      <header className="rc-admin-header">
        <h1 className="rc-admin-title">NEW EVENT</h1>
      </header>
      {result.ok ? (
        <NewEventForm games={result.data} />
      ) : (
        <p className="rc-admin-error">{result.message}</p>
      )}
    </main>
  );
}
