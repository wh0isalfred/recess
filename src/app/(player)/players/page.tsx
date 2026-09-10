/**
 * Minimal placeholder — REFERENCE in docs/SCREEN-STATUS.md, not a designed
 * screen. Exists only so the bottom nav (Player Shell V2) has somewhere
 * real to link to instead of a 404. Do not treat this as the Players
 * design; it isn't one.
 *
 * Phase 8.2: identity guard and PlayerShell wrapping both moved to the
 * shared (player)/layout.tsx — this page owns only its own content now.
 */
export default function PlayersPage() {
  return (
    <div className="rc-shell-placeholder">
      <p>Players is coming soon.</p>
    </div>
  );
}
