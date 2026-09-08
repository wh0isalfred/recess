export type StaffProfile = { name: string; role: "SUPER_ADMIN" | "EVENT_ADMIN" | "COORDINATOR" };

export type EventOverview = {
  event: {
    slug: string;
    name: string;
    status: string;
    startsAt: string;
    timezone: string;
    timezoneLabel: string;
    capacity: number;
  };
  counts: { registered: number; checkedIn: number; assigned: number; waiting: number };
  rooms: { id: string; label: string; position: number; capacity: number | null; occupancy: number }[];
  nextGame: { slug: string; name: string; roundCount: number } | null;
};

export type AdminRoom = {
  id: string;
  label: string;
  position: number;
  capacity: number | null;
  whatsappGroupUrl: string | null;
  occupancy: number;
  coordinator: { registrationId: string; alias: string; playerNumber: number; checkedInAt: string | null } | null;
};

/** A registration eligible to become a room's coordinator — see
 * admin_list_coordinator_candidates() (migration 0021). Never carries phone
 * or real name; alias/player number are enough for identification. */
export type CoordinatorCandidate = { registrationId: string; alias: string; playerNumber: number };

export type WaitingPlayer = { alias: string; playerNumber: number; checkedInAt: string };

export type RoomsOverview = { rooms: AdminRoom[]; waiting: WaitingPlayer[] };

export type RoomMember = { alias: string; playerNumber: number; assignedAt: string };

export type EventListItem = {
  slug: string;
  name: string;
  status: string;
  startsAt: string;
  timezone: string;
  timezoneLabel: string;
  registeredCount: number;
};

export type EventDetail = {
  slug: string;
  name: string;
  status: string;
  startsAt: string;
  timezone: string;
  timezoneLabel: string;
  registrationOpensAt: string | null;
  registrationClosesAt: string | null;
  checkinOpensAt: string | null;
  checkinClosesAt: string | null;
  capacity: number;
  whatsappGroupUrl: string | null;
  games: { eventGameId: string; gameId: string; slug: string; name: string; position: number }[];
  rooms: { id: string; label: string; position: number; capacity: number | null }[];
};

export type GameLibraryEntry = {
  id: string;
  slug: string;
  name: string;
  platform: "BROWSER" | "INSTALL" | "NATIVE";
  scoringTemplate: string;
  defaultRoundCount: number;
  defaultDurationMinutes: number | null;
};

/** One row of admin_list_event_games() — the Manage Event page's full
 * per-event-game configuration list, distinct from EventOverview's single
 * `nextGame` dashboard summary. */
export type EventGameConfig = {
  id: string;
  gameSlug: string;
  gameName: string;
  position: number;
  durationMinutes: number | null;
  plannedRounds: number;
};

export type AdminResult<T> = { ok: true; data: T } | { ok: false; code: string; message: string };
