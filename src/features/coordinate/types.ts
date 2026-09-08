/**
 * Mirrors coordinator_room_state()'s jsonb shape (migration 0029) — the
 * one combined read the Coordinator Home screen needs. See
 * ARCHITECTURE.md's scoring-engine section for the tables this is
 * assembled from; nothing here duplicates that logic, only its shape.
 */

export type RoomGameStatus = "PENDING" | "LIVE" | "COMPLETE";
export type ScoringTemplate = "PLACEMENT" | "ROLE_OUTCOME" | "TEAM_OUTCOME" | "INDIVIDUAL_OUTCOME" | "MANUAL";

export type RoleOutcomeAwards = Record<string, { win: number; loss: number }>;

export type CoordinatorRoomState = {
  room: {
    id: string;
    label: string;
    capacity: number | null;
    occupancy: number;
    roster: { registrationId: string; alias: string }[];
  };
  event: { slug: string; name: string };
  currentGame: {
    eventGameId: string;
    gameSlug: string;
    gameName: string;
    scoringTemplate: ScoringTemplate;
    /** For ROLE_OUTCOME: `{ awards: { <roleKey>: { win, loss } } }`. Read
     * the configured roles from here — never hardcode CREWMATE/IMPOSTOR. */
    scoringConfig: { awards?: RoleOutcomeAwards; type?: string };
    plannedRounds: number;
    durationMinutes: number | null;
    roomGameStatus: RoomGameStatus;
    startedAt: string | null;
    endedAt: string | null;
    completedRounds: number;
    liveRound: { roundId: string; roundIndex: number; startedAt: string } | null;
    lastCompletedRound: { roundId: string; roundIndex: number; endedAt: string } | null;
  } | null;
};

/** start_round()'s own return shape — the authoritative participant
 * snapshot. Used for result entry; never reconstructed from current room
 * membership (a late arrival must not appear here). */
export type RoundSnapshot = {
  roundId: string;
  roundIndex: number;
  participantCount: number;
  participants: { registrationId: string; alias: string }[];
};

export type RoleOutcomeParticipantInput = {
  registrationId: string;
  participation: "PARTICIPATING" | "DNP";
  role: string | null;
};

export type PlacementParticipantInput = {
  registrationId: string;
  participation: "PARTICIPATING" | "DNP";
  rawScore: number | null;
};

/** preview_round_result()'s own return shape. */
export type ResultPreview = {
  roundId: string;
  facts: {
    registrationId: string;
    alias: string;
    participation: "PARTICIPATING" | "DNP";
    role: string | null;
    rawScore: number | null;
  }[];
};

export type SubmitResultOutcome =
  | { ok: true; roundId: string; resultId: string; idempotent: boolean }
  | { ok: false; code: string; message: string };

/** room_standings()'s own return shape. */
export type RoomStandingRow = {
  registrationId: string;
  alias: string;
  totalPoints: number;
  placement: number;
  qualifies: boolean;
};
