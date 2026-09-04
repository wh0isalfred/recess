import type { Metadata } from "next";
import { redirect } from "next/navigation";
import { resolvePlayerIdentity } from "@/features/pass/actions";
import { IdentityCheckFailed } from "@/components/shared/IdentityCheckFailed";
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
 * Genuinely unregistered is a redirect to /register — this is the one place
 * that's correct. A resolution failure is not: bouncing a real registration
 * to /register on a transient error is exactly the "presented as an
 * unregistered visitor" the identity slice exists to prevent, so "unknown"
 * gets its own retry state instead of folding into the redirect.
 */
export const metadata: Metadata = {
  title: "RECESS",
};

export default async function PassPage() {
  const identity = await resolvePlayerIdentity();

  if (identity.status === "unregistered") redirect("/register");
  if (identity.status === "unknown") return <IdentityCheckFailed />;

  return <PassScreen state={identity.state} />;
}
