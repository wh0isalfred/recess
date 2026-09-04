/**
 * Next's route-level Suspense boundary for /register and its child routes
 * (alias, whatsapp) — covers all three from this one file, since none of
 * them define their own loading.tsx to override it. Shown only while the
 * server resolves getPlayerState() before deciding whether to redirect or
 * render onboarding; deliberately just the paper ground and nothing else,
 * so a slow connection sees a blank, on-brand pause rather than a flash of
 * white or a spinner that implies more is happening than "checking who you
 * are." Not a redesign — the onboarding screens themselves are untouched.
 */
export default function RegisterLoading() {
  return <div style={{ minHeight: "100svh", background: "var(--paper)" }} />;
}
