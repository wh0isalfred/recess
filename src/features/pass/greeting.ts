/**
 * "GOOD EVENING," — the hour read in the EVENT's timezone (WAT), the same
 * timezone every other date/time on this screen already uses, rather than
 * the viewer's local clock. A simple three-bucket split; nothing fancier
 * than that is worth the complexity for one word of copy.
 */
export function greetingFor(timezone: string, now: Date = new Date()): string {
  const hour = Number(
    new Intl.DateTimeFormat("en-US", { timeZone: timezone, hour: "numeric", hour12: false }).format(now),
  );
  if (hour < 12) return "GOOD MORNING,";
  if (hour < 17) return "GOOD AFTERNOON,";
  return "GOOD EVENING,";
}
