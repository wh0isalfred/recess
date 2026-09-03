"use server";

import { createClient } from "@/lib/supabase/server";
import { env } from "@/lib/env";
import { validateAlias, validateConsent, validateName, validatePhone, normalizeE164 } from "./validation";
import type { RegisterResult, RegistrationState } from "./types";

export type RegisterInput = {
  name: string;
  alias: string;
  phone: string;
  countryIso2: string;
  consent: boolean;
};

/**
 * Friendly text for every code register_player() can raise — see the
 * migration for the authoritative list. Anything not in this map (a raw
 * Postgres error, a network failure, a code this map hasn't been taught
 * yet) falls through to the generic message. Nothing from the database
 * reaches the player unfiltered.
 */
const FRIENDLY: Record<string, string> = {
  not_authenticated: "Your session expired. Refresh the page and try again.",
  invalid_name: "Enter your name.",
  invalid_alias: "Choose a RECESS name — 2-24 letters, numbers, dots, underscores or hyphens.",
  invalid_phone: "Enter a valid WhatsApp number.",
  consent_required: "You'll need to agree to continue.",
  event_not_found: "RECESS isn't open for registration right now.",
  registration_not_open: "Registration isn't open right now.",
  alias_taken: "That name is already taken — try another.",
};

const GENERIC = "Something went wrong. Please try again.";

function mapError(message: string): { code: string; message: string } {
  const [code] = message.split(":");
  return { code: code ?? "unknown", message: FRIENDLY[code] ?? GENERIC };
}

/**
 * Shape of one row from register_player() / get_my_registration(). No
 * generated Supabase types exist in this repo yet (no database.types.ts),
 * so this is hand-kept in parallel with the migration's `returns table` —
 * see supabase/migrations/20260901001600_registration.sql.
 */
type RegistrationRow = {
  registration_id: string;
  player_number: number;
  alias: string;
  registration_status: RegistrationState["status"];
  event_id: string;
  event_slug: string;
  event_name: string;
  starts_at: string;
  timezone: string;
  timezone_label: string;
  whatsapp_group_url: string | null;
};

function toRegistrationState(row: RegistrationRow): RegistrationState {
  return {
    registrationId: row.registration_id,
    playerNumber: row.player_number,
    alias: row.alias,
    status: row.registration_status,
    eventId: row.event_id,
    eventSlug: row.event_slug,
    eventName: row.event_name,
    startsAt: row.starts_at,
    timezone: row.timezone,
    timezoneLabel: row.timezone_label,
    whatsappGroupUrl: row.whatsapp_group_url,
  };
}

/**
 * The registration transaction boundary. Everything up to here (Screens
 * 03-05) is a local draft; this is the one place that writes anything real.
 *
 * Establishes the anonymous session per ARCHITECTURE.md §4.2 option A —
 * signInAnonymously() if this browser doesn't already have a session — then
 * calls register_player() as that session, so auth.uid() inside the function
 * is the id the registration gets linked to. Both happen against the same
 * server-side Supabase client so the session cookie @supabase/ssr sets is
 * the one the browser actually receives; nothing beyond the anon key is
 * used here, and the service-role client is never imported into this path.
 */
export async function submitRegistration(input: RegisterInput): Promise<RegisterResult> {
  const nameError = validateName(input.name);
  if (nameError) return { ok: false, code: "invalid_name", message: nameError };

  const aliasError = validateAlias(input.alias);
  if (aliasError) return { ok: false, code: "invalid_alias", message: aliasError };

  const phoneError = validatePhone(input.phone, input.countryIso2);
  if (phoneError) return { ok: false, code: "invalid_phone", message: phoneError };

  const consentError = validateConsent(input.consent);
  if (consentError) return { ok: false, code: "consent_required", message: consentError };

  const supabase = await createClient();

  const {
    data: { session },
  } = await supabase.auth.getSession();

  if (!session) {
    const { error: signInError } = await supabase.auth.signInAnonymously();
    if (signInError) {
      return {
        ok: false,
        code: "session_failed",
        message: "Could not start a session. Check your connection and try again.",
      };
    }
  }

  const { data, error } = await supabase
    .rpc("register_player", {
      p_event_slug: env.eventSlug(),
      p_real_name: input.name,
      p_alias: input.alias,
      p_phone_e164: normalizeE164(input.phone, input.countryIso2),
      p_consent: input.consent,
    })
    .single<RegistrationRow>();

  if (error) {
    const mapped = mapError(error.message);
    return { ok: false, ...mapped };
  }

  return { ok: true, registration: toRegistrationState(data) };
}
