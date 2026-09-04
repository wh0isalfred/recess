"use server";

import { createClient } from "@/lib/supabase/server";
import type {
  AdminResult,
  AdminRoom,
  EventDetail,
  EventListItem,
  EventOverview,
  GameLibraryEntry,
  RoomMember,
  RoomsOverview,
  StaffProfile,
} from "./types";

/**
 * Every admin page calls this first, server-side, before rendering anything.
 * This is the actual authorization boundary — the pages below only ever
 * decide what to *show* based on it, per "do not rely on hiding buttons."
 * Even if this check were skipped entirely, every RPC below re-checks
 * require_event_admin() itself (migration 0018) and refuses regardless —
 * this is the fast, friendly redirect in front of that, not a substitute
 * for it.
 */
export async function getStaffSession(): Promise<StaffProfile | null> {
  const supabase = await createClient();

  const {
    data: { session },
  } = await supabase.auth.getSession();
  if (!session) return null;

  const { data, error } = await supabase.rpc("get_my_staff_profile");
  if (error || !data) return null;

  return data as StaffProfile;
}

export type SignInResult = { ok: true } | { ok: false; message: string };

/**
 * Staff sign-in is ordinary email + password (ARCHITECTURE.md §4.2) — a
 * different Supabase Auth flow from the player's signInAnonymously(), and
 * never the same session. This never touches the anonymous-player path.
 */
export async function staffSignIn(email: string, password: string): Promise<SignInResult> {
  const supabase = await createClient();
  const { error } = await supabase.auth.signInWithPassword({ email, password });
  if (error) {
    return { ok: false, message: "Incorrect email or password." };
  }
  const staff = await getStaffSession();
  if (!staff) {
    await supabase.auth.signOut();
    return { ok: false, message: "This account is not set up for staff access." };
  }
  return { ok: true };
}

export async function staffSignOut(): Promise<void> {
  const supabase = await createClient();
  await supabase.auth.signOut();
}

const GENERIC = "Something went wrong. Please try again.";

function mapError(message: string): { code: string; message: string } {
  const [code] = message.split(":");
  const FRIENDLY: Record<string, string> = {
    not_authorized: "You don't have permission to do that.",
    event_not_found: "That event doesn't exist.",
    room_not_found: "That room doesn't exist.",
    game_not_found: "That game isn't in the library.",
    invalid_label: "Enter a room label.",
    invalid_capacity: "Capacity must be a positive number.",
    invalid_whatsapp_url: "That doesn't look like a WhatsApp group link.",
    invalid_staff: "That person isn't set up as staff yet.",
    invalid_name: "Enter an event name.",
    invalid_slug: "Enter an event slug.",
    invalid_position: "Something went wrong ordering the games — try again.",
    invalid_event: "Check the event details — a date, window or link looks wrong.",
    slug_taken: "An event with that URL slug already exists.",
    game_already_added: "That game is already in this event.",
  };
  return { code: code ?? "unknown", message: FRIENDLY[code ?? ""] ?? GENERIC };
}

async function callAdminRpc<T>(fn: string, args: Record<string, unknown>): Promise<AdminResult<T>> {
  try {
    const supabase = await createClient();
    const { data: { session } } = await supabase.auth.getSession();
    if (!session) return { ok: false, code: "not_authenticated", message: "Sign in required." };

    const { data, error } = await supabase.rpc(fn, args);
    if (error) return { ok: false, ...mapError(error.message) };
    return { ok: true, data: data as T };
  } catch {
    return { ok: false, code: "unknown", message: GENERIC };
  }
}

// ------------------------------------------------------------------- events

export async function fetchEventsList(): Promise<AdminResult<EventListItem[]>> {
  return callAdminRpc<EventListItem[]>("admin_list_events", {});
}

export async function fetchEventDetail(slug: string): Promise<AdminResult<EventDetail>> {
  return callAdminRpc<EventDetail>("admin_get_event", { p_event_slug: slug });
}

export async function fetchGamesLibrary(): Promise<AdminResult<GameLibraryEntry[]>> {
  return callAdminRpc<GameLibraryEntry[]>("admin_list_games", {});
}

export async function createEvent(input: {
  slug: string;
  name: string;
  startsAt: string;
  timezone: string;
  timezoneLabel: string;
  registrationOpensAt: string | null;
  registrationClosesAt: string | null;
  checkinOpensAt: string | null;
  checkinClosesAt: string | null;
  capacity: number;
  whatsappGroupUrl: string | null;
}): Promise<AdminResult<{ id: string; slug: string; status: string }>> {
  return callAdminRpc("admin_create_event", {
    p_slug: input.slug,
    p_name: input.name,
    p_starts_at: input.startsAt,
    p_timezone: input.timezone,
    p_timezone_label: input.timezoneLabel,
    p_registration_opens_at: input.registrationOpensAt,
    p_registration_closes_at: input.registrationClosesAt,
    p_checkin_opens_at: input.checkinOpensAt,
    p_checkin_closes_at: input.checkinClosesAt,
    p_capacity: input.capacity,
    p_whatsapp_group_url: input.whatsappGroupUrl,
  });
}

export async function addEventGame(
  eventSlug: string,
  gameId: string,
  position: number,
): Promise<AdminResult<{ id: string; gameSlug: string; position: number }>> {
  return callAdminRpc("admin_add_event_game", {
    p_event_slug: eventSlug,
    p_game_id: gameId,
    p_position: position,
  });
}

// -------------------------------------------------------------- per-event ops

export async function fetchEventOverview(slug: string): Promise<AdminResult<EventOverview>> {
  return callAdminRpc<EventOverview>("admin_event_overview", { p_event_slug: slug });
}

export async function fetchRoomsOverview(slug: string): Promise<AdminResult<RoomsOverview>> {
  return callAdminRpc<RoomsOverview>("admin_list_rooms", { p_event_slug: slug });
}

export async function upsertRoom(
  eventSlug: string,
  input: { roomId: string | null; label: string; capacity: number | null; whatsappGroupUrl: string | null },
): Promise<AdminResult<AdminRoom>> {
  return callAdminRpc<AdminRoom>("admin_upsert_room", {
    p_event_slug: eventSlug,
    p_room_id: input.roomId,
    p_label: input.label,
    p_capacity: input.capacity,
    p_whatsapp_group_url: input.whatsappGroupUrl,
  });
}

export async function assignCoordinator(
  eventSlug: string,
  roomId: string,
  userId: string | null,
): Promise<AdminResult<{ roomId: string; coordinatorUserId: string | null }>> {
  return callAdminRpc("admin_assign_coordinator", {
    p_event_slug: eventSlug,
    p_room_id: roomId,
    p_user_id: userId,
  });
}

export async function fetchRoomMembers(roomId: string): Promise<AdminResult<RoomMember[]>> {
  return callAdminRpc<RoomMember[]>("admin_room_members", { p_room_id: roomId });
}

export async function assignWaitingPlayers(
  eventSlug: string,
): Promise<AdminResult<{ assigned: number; stillWaiting: number }>> {
  return callAdminRpc("admin_assign_waiting_players", { p_event_slug: eventSlug });
}

/**
 * OPEN CHECK-IN calls the real lifecycle function, not a duplicate of its
 * rules — transition_event() (migration 0012) is the only place check-in
 * eligibility logic lives. admin_open_check_in() (migration 0018) is a thin
 * SECURITY DEFINER wrapper: it resolves the event server-side (RLS blocks a
 * raw table read from the browser's client regardless of role) and enforces
 * require_event_admin() before calling transition_event() — authorization
 * transition_event() itself deliberately does not perform.
 */
export async function openCheckIn(eventSlug: string): Promise<AdminResult<null>> {
  const result = await callAdminRpc<{ eventId: string; status: string }>("admin_open_check_in", {
    p_event_slug: eventSlug,
  });
  if (!result.ok) return result;
  return { ok: true, data: null };
}

/**
 * OPEN REGISTRATION — same shape as OPEN CHECK-IN above.
 * admin_open_registration() (migration 0019) wraps transition_event(),
 * which deliberately performs no authorization check of its own.
 */
export async function openRegistration(eventSlug: string): Promise<AdminResult<null>> {
  const result = await callAdminRpc<{ eventId: string; status: string }>("admin_open_registration", {
    p_event_slug: eventSlug,
  });
  if (!result.ok) return result;
  return { ok: true, data: null };
}
