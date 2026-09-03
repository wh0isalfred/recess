/**
 * The Screen 06 vs Screen 07 boundary.
 *
 * get_player_state() has no way to distinguish "just registered, seconds
 * ago" from "registered three days ago, checking the pass again" — both are
 * the same PASS_COUNTDOWN view, because they're the same fact about the
 * database. That distinction is pure UX (should this render feel like a
 * celebration or a calm status check?), not a security or data boundary, so
 * it doesn't need a database column to carry it.
 *
 * WhatsAppStep marks this flag the instant CLAIM MY SPOT succeeds, right
 * before navigating to /pass. /pass reads it once and clears it in the same
 * breath, so the celebration shows exactly once per real registration and a
 * refresh — or a return visit — lands on the calm Screen 07 instead. A
 * hard-refresh in the split second before the flag is read would also show
 * the celebration once more; accepted as the cost of not inventing a
 * database-backed "how new is this" timer for a purely cosmetic decision.
 *
 * sessionStorage, not the draft's own store: this outlives the draft, which
 * clearDraft() already wipes on success.
 */
const KEY = "recess.pass.fresh";

export function markPassFresh() {
  if (typeof window === "undefined") return;
  try {
    sessionStorage.setItem(KEY, "1");
  } catch {
    /* private mode, quota — worst case the celebration just doesn't show */
  }
}

/** Pure — safe for useSyncExternalStore's getSnapshot, which React may call more than once per render. */
export function hasPassFreshFlag(): boolean {
  if (typeof window === "undefined") return false;
  try {
    return sessionStorage.getItem(KEY) === "1";
  } catch {
    return false;
  }
}

/** The actual one-time consumption — call from a plain effect, never from getSnapshot. */
export function clearPassFreshFlag() {
  if (typeof window === "undefined") return;
  try {
    sessionStorage.removeItem(KEY);
  } catch {
    /* nothing to clean up if this throws */
  }
}
