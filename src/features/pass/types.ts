/**
 * Mirrors get_player_state()'s jsonb shape — see
 * supabase/migrations/20260901001700_check_in.sql, and ARCHITECTURE.md §2,
 * which specs this exact function ahead of any screen work: "one server
 * function returns the player's entire current state as a tagged union...
 * the React app renders whichever view comes back, it contains no rules
 * about which screen to show."
 *
 * `view` covers more than Screens 06-08 render for real. LATE_ARRIVAL,
 * LIVE_ROUND, BETWEEN_GAMES, PAUSED and RESULTS are tagged correctly by the
 * function (so it stays honest for any real event state) but have no
 * screen built yet — the client falls back to a plain, undesigned state for
 * those rather than pretending they're finished. WAITLISTED,
 * EVENT_CANCELLED, CANCELLED and MISSED_CHECK_IN are this phase's own
 * additions, named for facts the schema already produces.
 */
export type PlayerView =
  | "PASS_COUNTDOWN"
  | "CHECK_IN_OPEN"
  | "CHECKED_IN_WAITING"
  | "ROOM_ASSIGNED"
  | "WAITLISTED"
  | "EVENT_CANCELLED"
  | "CANCELLED"
  | "MISSED_CHECK_IN"
  | "LATE_ARRIVAL"
  | "LIVE_ROUND"
  | "BETWEEN_GAMES"
  | "PAUSED"
  | "RESULTS";

export type GamePlatform = "BROWSER" | "INSTALL" | "NATIVE";

export type PlayerStateGame = {
  slug: string;
  name: string;
  platform: GamePlatform;
};

export type PlayerState = {
  view: PlayerView;
  event: {
    slug: string;
    name: string;
    status: string;
    startsAt: string;
    timezone: string;
    timezoneLabel: string;
    /** Only ever present on the PASS_COUNTDOWN view — see the migration's room-privacy notes. */
    whatsappGroupUrl: string | null;
  };
  player: {
    alias: string;
    number: number;
    registrationStatus: "REGISTERED" | "WAITLISTED" | "CANCELLED";
    checkedInAt: string | null;
  };
  checkIn: {
    opensAt: string | null;
    closesAt: string | null;
    available: boolean;
  };
  /** Present only once a real membership exists. */
  room?: { label: string };
  /** Present only on the PASS_COUNTDOWN view. */
  games?: PlayerStateGame[];
};

export type CheckInResult =
  | { ok: true; state: PlayerState }
  | { ok: false; code: string; message: string };
