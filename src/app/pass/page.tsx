import type { Metadata } from "next";
import { redirect } from "next/navigation";
import { getPlayerState } from "@/features/pass/actions";
import { PassScreen } from "./PassScreen";

/**
 * `/pass` — the single surface a registered player's session resolves to.
 * ARCHITECTURE.md §5 names this route ahead of any screen work, and §2
 * names get_player_state() as the one function that decides what renders:
 * "the React app renders whichever view comes back, it contains no rules
 * about which screen to show." This route is that render step — the
 * decision itself lives in the database and in PassScreen's dispatch on
 * `state.view`, not here.
 *
 * Reads the session already on the request — never signs anyone in — so a
 * visitor with no registration is a plain "you're not registered" case, not
 * an error.
 */
export const metadata: Metadata = {
  title: "RECESS",
};

export default async function PassPage() {
  const state = await getPlayerState();

  if (!state) {
    redirect("/register");
  }

  return <PassScreen state={state} />;
}
