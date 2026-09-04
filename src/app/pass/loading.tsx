/**
 * /pass's ground colour depends on the resolved view (paper for
 * PASS_COUNTDOWN, night for everything past check-in) — this loading state
 * can't know which in advance, so it picks paper as the more common
 * pre-event case rather than guessing per-visit. The visible cost is a
 * brief, imperfect flash of paper right before a night-ground view settles
 * in on a slow connection; accepted as minor and cosmetic rather than
 * something worth adding client-side state to avoid.
 */
export default function PassLoading() {
  return <div style={{ minHeight: "100svh", background: "var(--paper)" }} />;
}
