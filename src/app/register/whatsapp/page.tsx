import type { Metadata } from "next";
import { redirect } from "next/navigation";
import { resolvePlayerIdentity } from "@/features/pass/actions";
import { IdentityCheckFailed } from "@/components/shared/IdentityCheckFailed";
import { WhatsAppStep } from "./WhatsAppStep";

export const metadata: Metadata = {
  title: "Register — RECESS",
};

/**
 * Same guard as /register — see the comment there. This is the step most
 * likely to be hit by the back button right after a successful submit:
 * clearDraft() has already run and the real registration exists by then, so
 * this redirects to /pass rather than re-showing a form whose CLAIM MY SPOT
 * would just find the same registration again (database idempotency, 0016)
 * — belt-and-suspenders, not the only thing standing between a double
 * back-press and a duplicate.
 */
export default async function WhatsAppPage() {
  const identity = await resolvePlayerIdentity();
  if (identity.status === "registered") redirect("/pass");
  if (identity.status === "unknown") return <IdentityCheckFailed />;

  return <WhatsAppStep />;
}
