import type { Metadata } from "next";
import { redirect } from "next/navigation";
import { resolvePlayerIdentity } from "@/features/pass/actions";
import { IdentityCheckFailed } from "@/components/shared/IdentityCheckFailed";
import { AliasStep } from "./AliasStep";

export const metadata: Metadata = {
  title: "Your RECESS name — RECESS",
};

/**
 * Same guard as /register — see the comment there.
 */
export default async function AliasPage() {
  const identity = await resolvePlayerIdentity();
  if (identity.status === "registered") redirect("/pass");
  if (identity.status === "unknown") return <IdentityCheckFailed />;

  return <AliasStep />;
}
