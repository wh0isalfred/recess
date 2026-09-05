/**
 * Pass V2's event block splits date and weekday/time onto separate lines
 * ("11 SEPT 2026" / "FRIDAY · 8:00 PM WAT"), unlike calendar.ts's combined
 * `formatEventDate` ("FRIDAY · 11 SEPT 2026") which Screen 06/07/08 already
 * render as-is. Small, separate formatters here rather than changing that
 * shared one out from under already-approved screens.
 */
export function formatDateOnly(startsAt: string, timezone: string): string {
  const date = new Date(startsAt);
  const day = new Intl.DateTimeFormat("en-GB", { day: "numeric", timeZone: timezone }).format(date);
  const month = new Intl.DateTimeFormat("en-GB", { month: "short", timeZone: timezone })
    .format(date)
    .toUpperCase();
  const year = new Intl.DateTimeFormat("en-GB", { year: "numeric", timeZone: timezone }).format(date);
  return `${day} ${month} ${year}`;
}

export function formatWeekdayOnly(startsAt: string, timezone: string): string {
  return new Intl.DateTimeFormat("en-GB", { weekday: "long", timeZone: timezone })
    .format(new Date(startsAt))
    .toUpperCase();
}
