import type { Metadata } from "next";
import { redirect } from "next/navigation";
import { getMyRegistration } from "@/features/registration/actions";
import { PassScreen } from "./PassScreen";

/**
 * `/pass` — the single surface a registered player's session resolves to.
 * ARCHITECTURE.md §5 names this route ahead of any screen work: "the state
 * machine surface — countdown, check-in, room, live, results all render
 * here." This phase only has REGISTERED/WAITLISTED to show (Screen 06); the
 * later states join the same route rather than getting their own, so a
 * refresh or a reopened WhatsApp link always lands somewhere that still
 * knows who the player is.
 *
 * Reads the session already on the request — never signs anyone in — so a
 * visitor with no registration is a plain "you're not registered" case, not
 * an error.
 */
export const metadata: Metadata = {
  title: "You're in — RECESS",
};

export default async function PassPage() {
  const registration = await getMyRegistration();

  if (!registration) {
    redirect("/register");
  }

  return <PassScreen registration={registration} />;
}
