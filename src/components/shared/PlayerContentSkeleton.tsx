/**
 * Registered-player route-transition loading state (Phase 8.2). Rendered
 * by (player)/loading.tsx, which Next.js swaps in for the content slot
 * only — the shared layout (PlayerShell, the persistent bottom nav) stays
 * mounted around it, since loading.tsx is a sibling boundary to the page,
 * not a replacement of the layout itself.
 *
 * Approximate content dimensions (a heading-sized bar, a few body-line-
 * sized bars, a card-sized block) rather than a blank slot, so the
 * transition doesn't cause a visible layout jump once real content
 * arrives. Static bars, gently pulsing — no shimmer sweep, no skeleton
 * "wave" animation, and no motion at all when prefers-reduced-motion is
 * set (loaders.css).
 */
export function PlayerContentSkeleton() {
  return (
    <div className="rc-skeleton" role="status" aria-label="Loading">
      <div className="rc-skeleton-bar rc-skeleton-bar--heading" />
      <div className="rc-skeleton-bar rc-skeleton-bar--line" />
      <div className="rc-skeleton-bar rc-skeleton-bar--line rc-skeleton-bar--short" />
      <div className="rc-skeleton-card" />
    </div>
  );
}
