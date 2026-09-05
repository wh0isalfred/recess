import type { Metadata } from "next";
import { resolvePlayerIdentity } from "@/features/pass/actions";
import { getPublicEventInfo } from "@/features/landing/event";
import { Landing } from "./Landing";

export const metadata: Metadata = {
  title: "RECESS",
  description:
    "RECESS is our night to embrace that inner child and have real fun. Friday 11 September 2026, 8:00 PM WAT.",
};

export default async function HomePage() {
  // Landing's CTA is low-stakes compared to the onboarding guards: worst
  // case on a resolution failure, a registered player sees I'M IN instead
  // of OPEN YOUR PASS and clicks through to /register — which resolves
  // identity again itself and either redirects them straight to /pass or
  // shows its own retry state. Defaulting to "unregistered" here rather
  // than adding a second retry surface is a deliberate choice, not the same
  // shortcut the onboarding guards specifically avoid.
  const identity = await resolvePlayerIdentity();
  const event = await getPublicEventInfo();

  return <Landing event={event} registered={identity.status === "registered"} />;
}
