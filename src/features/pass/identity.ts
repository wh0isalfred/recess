import type { PlayerState } from "./types";

export type IdentityResolution =
  | { status: "unregistered" }
  | { status: "registered"; state: PlayerState }
  | { status: "unknown" };

/**
 * The actual decision table for resolvePlayerIdentity() (see
 * src/features/pass/actions.ts), pulled out as a pure function so every
 * branch can be exercised directly with representative inputs — no live
 * Supabase project needed to prove the *logic* is correct, only to prove
 * the I/O gathering the signals around it.
 *
 * Three genuinely distinguishable outcomes:
 *
 *   1. No authenticated session at all -> "unregistered." Unambiguous: with
 *      no session there is no identity to look anything up for.
 *
 *   2. A session exists but the identity/state lookup could not be
 *      completed — the Supabase client itself failed to construct, the
 *      session check threw, or the get_player_state() RPC threw or
 *      returned an error -> "unknown." Never re-interpreted as "no
 *      registration": an earlier version funnelled `error || !data` into
 *      one `return null`, so an RPC failure for an actually-registered
 *      player looked identical to a legitimate empty result, and every
 *      caller downstream treated it as "show them onboarding again." This
 *      function exists specifically so that bug cannot recur silently.
 *
 *   3. A session exists, the RPC call succeeded cleanly (no throw, no
 *      error), and the data itself is null -> "unregistered."
 *      get_player_state() (0017/0018) returns SQL null only when
 *      auth.uid() has no registration — a deliberate, error-free null, not
 *      a failure. This is the only path that produces "unregistered" once
 *      a session exists, and it is reached only when nothing upstream
 *      failed.
 */
export function classifyIdentity(signals: {
  clientFailed: boolean;
  sessionCheckFailed: boolean;
  hasSession: boolean;
  rpcThrew: boolean;
  rpcError: boolean;
  rpcData: unknown;
}): IdentityResolution {
  if (signals.clientFailed || signals.sessionCheckFailed) return { status: "unknown" };
  if (!signals.hasSession) return { status: "unregistered" };
  if (signals.rpcThrew || signals.rpcError) return { status: "unknown" };
  if (!signals.rpcData) return { status: "unregistered" };
  return { status: "registered", state: signals.rpcData as PlayerState };
}
