import type { Metadata } from "next";
import { redirect } from "next/navigation";
import { resolvePlayerIdentity } from "@/features/pass/actions";
import { IdentityCheckFailed } from "@/components/shared/IdentityCheckFailed";
import { NameStep } from "./NameStep";

export const metadata: Metadata = {
  title: "Register — RECESS",
};

/**
 * The onboarding route guard, repeated identically on all three
 * registration steps (this file, alias/page.tsx, whatsapp/page.tsx). A
 * player with no real registration (resolvePlayerIdentity() ->
 * "unregistered" — a draft in sessionStorage is not a registration, see
 * migration 0017/0018) is free to be here regardless of how much local
 * draft progress exists. A genuine resolution failure ("unknown") is its
 * own outcome, not silently treated as unregistered — see
 * resolvePlayerIdentity()'s own comment for why that distinction matters.
 */
export default async function RegisterPage() {
  const identity = await resolvePlayerIdentity();
  if (identity.status === "registered") redirect("/pass");
  if (identity.status === "unknown") return <IdentityCheckFailed />;

  return <NameStep />;
}
