/**
 * Shape of a row from register_player() / get_my_registration() — see
 * supabase/migrations/20260901001600_registration.sql. Both submitRegistration
 * (src/features/registration/actions.ts) and /pass (src/app/pass/page.tsx)
 * use this, so a real registration and a recovered one carry identical data.
 */
export type RegistrationState = {
  registrationId: string;
  playerNumber: number;
  alias: string;
  status: "REGISTERED" | "WAITLISTED" | "CANCELLED";
  eventId: string;
  eventSlug: string;
  eventName: string;
  startsAt: string;
  timezone: string;
  timezoneLabel: string;
  whatsappGroupUrl: string | null;
};

export type RegisterResult =
  | { ok: true; registration: RegistrationState }
  | { ok: false; code: string; message: string };
