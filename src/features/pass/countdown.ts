/**
 * "03 DAYS TO GO" — a whole-day count of calendar days between today and
 * the event, both read in the EVENT's own timezone (not the viewer's, and
 * not a raw hours/24 division, which would read "2 days" late in the day
 * before a night event actually happening). Deterministic: two calendar
 * dates, subtracted, with the boundaries the event's own database status
 * already makes possible.
 */
export type Countdown =
  | { kind: "future"; days: number }
  | { kind: "today" }
  | { kind: "past" };

function calendarDateIn(instant: Date, timeZone: string): number {
  // A UTC midnight instant carrying only the event's own calendar date, so
  // subtracting two of these is a clean day count with no DST/offset noise.
  const parts = new Intl.DateTimeFormat("en-CA", {
    timeZone,
    year: "numeric",
    month: "2-digit",
    day: "2-digit",
  }).formatToParts(instant);
  const y = parts.find((p) => p.type === "year")!.value;
  const m = parts.find((p) => p.type === "month")!.value;
  const d = parts.find((p) => p.type === "day")!.value;
  return Date.UTC(Number(y), Number(m) - 1, Number(d));
}

export function countdownTo(startsAt: string, timezone: string, now: Date = new Date()): Countdown {
  const eventDay = calendarDateIn(new Date(startsAt), timezone);
  const today = calendarDateIn(now, timezone);
  const days = Math.round((eventDay - today) / 86_400_000);

  if (days > 0) return { kind: "future", days };
  if (days === 0) return { kind: "today" };
  return { kind: "past" };
}
