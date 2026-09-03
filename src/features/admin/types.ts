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
  coordinator: { userId: string; name: string } | null;
};

export type WaitingPlayer = { alias: string; playerNumber: number; checkedInAt: string };

export type RoomsOverview = { rooms: AdminRoom[]; waiting: WaitingPlayer[] };

export type RoomMember = { alias: string; playerNumber: number; assignedAt: string };

export type AdminResult<T> = { ok: true; data: T } | { ok: false; code: string; message: string };
