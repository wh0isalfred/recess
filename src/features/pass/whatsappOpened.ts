/**
 * The WhatsApp CTA's "opened" state — Pass V2's pre-event primary action.
 *
 * We only ever know the player clicked through to WhatsApp, never that they
 * actually joined the group (an external app, outside our control). This
 * persists that one fact, scoped to the real `event id + registration id`
 * (not display numbering like the event slug or player number, which can
 * change independently of identity — e.g. an event's slug is editable
 * content, and this key must track the actual record, not its label), so:
 *   - a refresh does not re-show the hot-pink "first open" state;
 *   - registering for a *different* future event starts fresh, because the
 *     key includes that event's own id.
 *
 * localStorage, not sessionStorage: unlike the pass-fresh flag (a once-ever
 * cosmetic flourish, cleared the instant it's read), this needs to survive
 * closing the tab and coming back days later, right up until check-in.
 */
function keyFor(eventId: string, registrationId: string): string {
  return `recess:whatsapp-opened:${eventId}:${registrationId}`;
}

export function hasOpenedWhatsApp(eventId: string, registrationId: string): boolean {
  if (typeof window === "undefined") return false;
  try {
    return localStorage.getItem(keyFor(eventId, registrationId)) === "1";
  } catch {
    return false;
  }
}

export function markWhatsAppOpened(eventId: string, registrationId: string) {
  if (typeof window === "undefined") return;
  try {
    localStorage.setItem(keyFor(eventId, registrationId), "1");
  } catch {
    /* private mode, quota — worst case the CTA just stays pink next visit */
  }
}
