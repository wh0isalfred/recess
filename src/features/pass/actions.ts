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
