import type { Metadata } from "next";
import { redirect } from "next/navigation";
import { resolvePlayerIdentity } from "@/features/pass/actions";
import { IdentityCheckFailed } from "@/components/shared/IdentityCheckFailed";
import { AccessView } from "./AccessView";

export const metadata: Metadata = {
  title: "Open your pass — RECESS",
};

/**
 * /access — the returning-player recovery flow. A session that's already
 * recognized (resolvePlayerIdentity() -> "registered") is sent straight to
 * /pass, exactly like Landing's own primary CTA would already do for them
 * — this route only has work to do for an unrecognized session.
 */
export default async function AccessPage() {
  const identity = await resolvePlayerIdentity();
  if (identity.status === "registered") redirect("/pass");
  if (identity.status === "unknown") return <IdentityCheckFailed />;

  return <AccessView />;
}
