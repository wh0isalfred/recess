import type { Metadata } from "next";
import { resolvePlayerIdentity } from "@/features/pass/actions";
import { ArrivalLanding, type EventCard } from "./ArrivalLanding";

/**
 * Placeholder event card for the visual pass. Screen 02's data column is not
 * connected yet — this moves to the event record in the CONNECT step, per
 * docs/SCREEN-STATUS.md. Nothing downstream reads these strings.
 */
const EVENT: EventCard = {
  day: "FRI",
  date: "11",
  monthYear: "SEPT 2026",
  time: "8:00",
  meridiem: "PM",
  zone: "WAT",
};

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

  return <ArrivalLanding event={EVENT} registered={identity.status === "registered"} />;
}
