"use server";

import { createClient } from "@/lib/supabase/server";
import type { CheckInResult, PlayerState } from "./types";
import { classifyIdentity, type IdentityResolution } from "./identity";

export type { IdentityResolution } from "./identity";

/**
 * The one identity check every onboarding guard and the landing page's CTA
 * share (see register/page.tsx, register/alias/page.tsx,
 * register/whatsapp/page.tsx, src/app/pass/page.tsx, and src/app/page.tsx)
 * — "do not duplicate this logic independently across every screen."
 *
 * Three genuinely distinguishable outcomes, checked in this order:
 *
 *   1. No authenticated session at all -> "unregistered." Unambiguous: with
 *      no session there is no identity to look anything up for, so this
 *      never calls the RPC and never has an error to swallow.
 *
 *   2. A session exists and the RPC call itself fails — throws, or returns
 *      a Postgres/network error — -> "unknown." A real, authenticated
 *      identity's lookup did not complete. This is never re-interpreted as
 *      "no registration," which is the specific bug this function exists to
 *      not have: an earlier version funnelled `error || !data` into one
 *      `return null`, so an RPC failure for an actually-registered player
 *      looked identical to a legitimate empty result, and every caller
 *      downstream treated it as "show them onboarding again."
 *
 *   3. A session exists, the RPC call succeeds cleanly, and the data itself
 *      is null -> "unregistered." get_player_state() (0017/0018) returns
 *      SQL null only when auth.uid() has no registration — a deliberate,
 *      error-free null, not a failure. This is the only path that produces
 *      "unregistered" once a session exists; it never happens by falling
 *      through an error branch.
 *
 * Every failure mode below returns "unknown," not a silent default in
 * either direction — an onboarding guard renders an explicit retry state
 * for it, never onboarding and never a redirect. See IdentityCheckFailed.
 */
export async function resolvePlayerIdentity(): Promise<IdentityResolution> {
  let supabase: Awaited<ReturnType<typeof createClient>> | undefined;
  try {
    supabase = await createClient();
  } catch {
    return classifyIdentity({
      clientFailed: true, sessionCheckFailed: false, hasSession: false,
      rpcThrew: false, rpcError: false, rpcData: undefined,
    });
  }

  let hasSession = false;
  try {
    const result = await supabase.auth.getSession();
    hasSession = !!result.data.session;
  } catch {
    return classifyIdentity({
      clientFailed: false, sessionCheckFailed: true, hasSession: false,
      rpcThrew: false, rpcError: false, rpcData: undefined,
    });
  }

  if (!hasSession) {
    return classifyIdentity({
      clientFailed: false, sessionCheckFailed: false, hasSession: false,
      rpcThrew: false, rpcError: false, rpcData: undefined,
    });
  }

  let rpcThrew = false;
  let rpcError = false;
  let rpcData: unknown;
  try {
    const result = await supabase.rpc("get_player_state");
    rpcError = !!result.error;
    rpcData = result.data;
  } catch {
    rpcThrew = true;
  }

  return classifyIdentity({
    clientFailed: false, sessionCheckFailed: false, hasSession: true,
    rpcThrew, rpcError, rpcData,
  });
}

/**
 * Friendly text for every code check_in_player() can raise — see the
 * migration for the authoritative list. Anything else falls through to a
 * generic message; no raw Postgres/Supabase error ever reaches the player.
 */
const FRIENDLY: Record<string, string> = {
  not_authenticated: "Your session expired. Refresh the page and try again.",
  not_registered: "We couldn't find your registration. Try refreshing.",
  waitlisted: "You're on the waitlist — check-in opens once you're confirmed.",
  cancelled: "This registration was cancelled.",
  check_in_not_open: "Check-in isn't open yet.",
  check_in_closed: "Check-in has closed.",
};

const GENERIC = "Something went wrong. Please try again.";

export async function checkIn(): Promise<CheckInResult> {
  const supabase = await createClient();

  const {
    data: { session },
  } = await supabase.auth.getSession();
  if (!session) {
    return { ok: false, code: "not_authenticated", message: FRIENDLY.not_authenticated };
  }

  const { data, error } = await supabase.rpc("check_in_player");
  if (error) {
    const [code] = error.message.split(":");
    return { ok: false, code: code ?? "unknown", message: FRIENDLY[code ?? ""] ?? GENERIC };
  }

  return { ok: true, state: data as PlayerState };
}
