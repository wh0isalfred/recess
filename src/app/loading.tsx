/**
 * Applies only to "/" itself — every other route with its own identity
 * check (register/loading.tsx, pass/loading.tsx) overrides this for its own
 * segment. Landing's CTA now depends on getPlayerState() (see page.tsx) to
 * decide I'M IN vs OPEN YOUR PASS; this is what a slow connection sees
 * while that resolves, instead of the arrival splash flashing in with the
 * wrong CTA and then correcting itself.
 */
export default function HomeLoading() {
  return <div style={{ minHeight: "100svh", background: "var(--paper)" }} />;
}
