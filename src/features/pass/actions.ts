"use server";

import { createClient } from "@/lib/supabase/server";
import type { CheckInResult, PlayerState } from "./types";

/**
 * `/pass`'s single data source. Reads the session already on the request —
 * never signs anyone in — so a visitor with no session or no registration
 * gets null, which the page reads as "not registered" rather than an error.
 */
export async function getPlayerState(): Promise<PlayerState | null> {
  const supabase = await createClient();

  const {
    data: { session },
  } = await supabase.auth.getSession();
  if (!session) return null;

  const { data, error } = await supabase.rpc("get_player_state");
  if (error || !data) return null;

  return data as PlayerState;
}

/**
 * The one identity check every onboarding guard and the landing page's CTA
 * share (see register/page.tsx, register/alias/page.tsx,
 * register/whatsapp/page.tsx, and src/app/page.tsx) — "do not duplicate
 * this logic independently across every screen."
 *
 * getPlayerState() itself only distinguishes "no registration" from "has
 * one" — it cannot tell that apart from "couldn't check right now" (a
 * network blip, Supabase briefly unreachable), because both surface as a
 * thrown exception or an RPC error with nothing else to go on. Collapsing
 * that into null would satisfy the type system while violating the actual
 * product invariant this slice exists to guarantee: a genuinely registered
 * player must never be shown as unregistered, including when the check
 * itself fails. So this wraps getPlayerState() and keeps "unknown" as its
 * own outcome, forcing every caller to decide deliberately rather than by
 * accident — an onboarding guard should render a retry state for "unknown,"
 * never silently fall through to registration.
 */
export type IdentityResolution =
  | { status: "unregistered" }
  | { status: "registered"; state: PlayerState }
  | { status: "unknown" };

export async function resolvePlayerIdentity(): Promise<IdentityResolution> {
  try {
    const state = await getPlayerState();
    return state ? { status: "registered", state } : { status: "unregistered" };
  } catch {
    return { status: "unknown" };
  }
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
