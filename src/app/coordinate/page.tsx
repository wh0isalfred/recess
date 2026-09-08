import type { Metadata } from "next";
import { redirect } from "next/navigation";
import { resolvePlayerIdentity } from "@/features/pass/actions";
import { IdentityCheckFailed } from "@/components/shared/IdentityCheckFailed";
import { CoordinateView } from "@/features/coordinate/CoordinateView";

/**
 * /coordinate — reuses the exact same identity resolution every other
 * player screen goes through (resolvePlayerIdentity(), the one function
 * ARCHITECTURE.md names as the single source of "who is this session and
 * what is their state"). No separate coordinator login exists or is
 * created here.
 *
 * Access is decided by get_player_state()'s own `coordinating` field
 * (migration 0029), not by whether someone reached this URL — a
 * non-coordinator who knows this route sees the same redirect an
 * unregistered visitor would, never a glimpse of coordinator controls.
 * The real authority is still server-side on every mutating call below
 * this page (is_authorized_for_room(), enforced inside each RPC) — this
 * check is only what decides whether the page renders at all.
 */
export const metadata: Metadata = {
  title: "Coordinate — RECESS",
};

export default async function CoordinatePage() {
  const identity = await resolvePlayerIdentity();

  if (identity.status === "unregistered") redirect("/pass");
  if (identity.status === "unknown") return <IdentityCheckFailed />;

  const coordinating = identity.state.coordinating;
  if (!coordinating) redirect("/pass");

  return <CoordinateView roomId={coordinating.roomId} roomLabel={coordinating.roomLabel} />;
}
