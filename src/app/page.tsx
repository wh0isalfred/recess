import type { Metadata } from "next";
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

export default function HomePage() {
  return <ArrivalLanding event={EVENT} />;
}
