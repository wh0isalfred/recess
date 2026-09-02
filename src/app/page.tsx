import type { Metadata } from "next";
import { ArrivalLanding, type EventCard } from "./ArrivalLanding";

/**
 * Runs before paint, so the entrance never flashes.
 *
 * Sets `html[data-arrival="fresh"]` on the first arrival of a browser session
 * only, and never when the visitor has asked for reduced motion. Session
 * scope means moving around the product does not replay the entrance, and it
 * costs nothing at the database — the whole memory is one sessionStorage key.
 */
const ARRIVAL_GUARD = `(function(){try{var k="recess.arrival";if(!sessionStorage.getItem(k)&&!matchMedia("(prefers-reduced-motion: reduce)").matches){document.documentElement.dataset.arrival="fresh"}sessionStorage.setItem(k,"1")}catch(e){}})()`;

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
  return (
    <>
      <script dangerouslySetInnerHTML={{ __html: ARRIVAL_GUARD }} />
      <ArrivalLanding event={EVENT} />
    </>
  );
}
