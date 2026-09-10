import { PlayerContentSkeleton } from "@/components/shared/PlayerContentSkeleton";

/**
 * Phase 8.2 — the registered-player content-area loading state. Next.js
 * renders this INSIDE the shared (player)/layout.tsx's own render tree —
 * PlayerShell (the canvas + persistent bottom nav) stays exactly as it
 * was, already mounted; only the slot where a page's own content would go
 * shows this skeleton while that page's data is still resolving. This is
 * the concrete difference from the old per-page architecture, where
 * there was no boundary that could keep the shell mounted at all.
 */
export default function PlayerLoading() {
  return <PlayerContentSkeleton />;
}
