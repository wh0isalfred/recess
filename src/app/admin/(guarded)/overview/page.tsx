import type { Metadata } from "next";
import { fetchEventOverview } from "@/features/admin/actions";
import { OverviewView } from "./OverviewView";

export const metadata: Metadata = { title: "Overview — RECESS Admin" };

export default async function AdminOverviewPage() {
  const result = await fetchEventOverview();

  if (!result.ok) {
    return (
      <main className="rc-admin-page">
        <p className="rc-admin-error">{result.message}</p>
      </main>
    );
  }

  return <OverviewView data={result.data} />;
}
