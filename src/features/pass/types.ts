/**
 * Mirrors get_player_state()'s jsonb shape — see
 * supabase/migrations/20260901003200_player_live_v2.sql (latest), and
 * ARCHITECTURE.md §2, which specs this exact function ahead of any screen
 * work: "one server function returns the player's entire current state as
 * a tagged union... the React app renders whichever view comes back, it
 * contains no rules about which screen to show."
 *
 * Phase 8.3 Gate B: LIVE_ROUND, BETWEEN_ROUNDS (new), BETWEEN_GAMES,
 * PAUSED, QUALIFIED (new), NOT_QUALIFIED (new) are now genuinely produced
 * and fully backed by real screens. LATE_ARRIVAL and RESULTS remain
 * honest placeholders — LATE_ARRIVAL because the backend doesn't yet
 * distinguish it from ordinary ROOM_ASSIGNED, RESULTS because no finale/
 * final-results engine exists yet (see docs/SCREEN-STATUS.md).
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
  | "BETWEEN_ROUNDS"
  | "BETWEEN_GAMES"
  | "PAUSED"
  | "QUALIFIED"
  | "NOT_QUALIFIED"
  | "RESULTS";

export type GamePlatform = "BROWSER" | "INSTALL" | "NATIVE";
export type ScoringTemplate = "PLACEMENT" | "ROLE_OUTCOME" | "TEAM_OUTCOME" | "INDIVIDUAL_OUTCOME" | "MANUAL";

export type PlayerStateGame = {
  slug: string;
  name: string;
  platform: GamePlatform;
  /** Card-sized artwork — may be null, or may point at a file that isn't
   * actually present in /public/games yet. Always render through
   * <GameArtwork>, never a bare <img>. */
  artworkUrl: string | null;
  iconUrl: string | null;
};

export type YourRoundFact =
  | { participation: "PARTICIPATING"; role: string }
  | { participation: "PARTICIPATING"; rawScore: number }
  | { participation: "DNP" };

export type ActiveGame = {
  gameSlug: string;
  gameName: string;
  platform: GamePlatform;
  platformUrl: string | null;
  artworkUrl: string | null;
  scoringTemplate: ScoringTemplate;
  plannedRounds: number;
  completedRounds: number;
  durationMinutes: number | null;
  startedAt: string | null;
  liveRound: { roundIndex: number } | null;
  lastRoundResult: {
    roundIndex: number;
    /** The round's real confirmation timestamp — never a transient
     * client-invented flag. A brief "round confirmed" animation may be
     * triggered client-side by observing this value change; it is never
     * itself a piece of authoritative state. */
    confirmedAt: string;
    yourFact: YourRoundFact;
    /** True while a correction request against this result is PENDING.
     * Never accompanied by the reason or proposed payload — those are
     * Admin-only. */
    pending: boolean;
  } | null;
  /**
   * True only when this room-game has no live round and is now legally
   * eligible for complete_room_game() — the exact same rule that
   * function itself enforces (room_game_ready_to_settle(), shared, not
   * duplicated). When true: "Game done. Scores are being finalized." —
   * never "next round starting soon."
   */
  awaitingGameSettlement: boolean;
};

export type LastCompletedGame = {
  gameSlug: string;
  gameName: string;
  /** Settled, game-level RECESS championship points. Never a per-round
   * figure — there is no such thing. 0 for a real zero score, never
   * null once this field exists at all. */
  yourGamePoints: number;
  /** Null when leaderboard_visibility hides comparative standings at
   * this point in the event — never omit the distinction by guessing. */
  roomPlacementThisGame: number | null;
};

export type Championship = {
  yourTotalPoints: number;
  qualifies: boolean;
  /** Null when leaderboard_visibility hides comparative standings —
   * qualifies is still computed and shown even when this is hidden. */
  roomPlacement: number | null;
  finaleInProgress: boolean;
  finalResults: {
    yourFinalPoints: number;
    /** No finale engine exists yet — always empty until Gate C builds
     * one. Never fabricate a name here. */
    champions: string[];
  } | null;
};

export type PlayerState = {
  view: PlayerView;
  event: {
    id: string;
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
    registrationId: string;
    alias: string;
    number: number;
    registrationStatus: "REGISTERED" | "WAITLISTED" | "CANCELLED";
    checkedInAt: string | null;
    /** Permanent per-player identity — assigned once, migration 0020. */
    avatarColor: string;
  };
  checkIn: {
    opensAt: string | null;
    closesAt: string | null;
    available: boolean;
  };
  /** Present from ROOM_ASSIGNED onward — the player is still in this
   * room throughout every later room-stage state. */
  room?: {
    label: string;
    capacity: number | null;
    occupancy: number;
    whatsappGroupUrl: string | null;
    /** The caller's own current room only — never another room's roster. */
    roster: { alias: string }[];
    /** The room's active coordinator's alias only — never their
     * registrationId, phone, or real name. */
    coordinatorAlias: string | null;
  };
  /** Present only for LIVE_ROUND / BETWEEN_ROUNDS. Replaces the old
   * `currentGame` naming — this field means "happening right now,"
   * nothing else. */
  activeGame?: ActiveGame | null;
  /** Present only for BETWEEN_GAMES / QUALIFIED / NOT_QUALIFIED — a
   * genuinely settled game, never an in-progress one. */
  lastCompletedGame?: LastCompletedGame | null;
  /**
   * The next configured game in this room's sequence. Present for
   * ROOM_ASSIGNED (the first game) and BETWEEN_GAMES (whatever's next);
   * null for QUALIFIED/NOT_QUALIFIED, since there is no next game.
   */
  nextGame?: PlayerStateGame | null;
  /**
   * @deprecated Additive compatibility field, present only alongside
   * ROOM_ASSIGNED, mirroring `nextGame` exactly. Kept only so an
   * already-deployed frontend build doesn't break during a migration/
   * frontend deployment-order mismatch — see migration 0032's own
   * comment. Read `nextGame` in new code; remove this once the old
   * frontend build is confirmed retired.
   */
  upFirstGame?: PlayerStateGame | null;
  /** Present only on the PASS_COUNTDOWN view. */
  games?: PlayerStateGame[];
  /**
   * Present only on the PASS_COUNTDOWN view — migration 0020. alias +
   * avatarColor only, admitted (REGISTERED) players only, ordered by
   * player_number. `avatars`/`previewAliases` are capped server-side (6/3);
   * the remainder for "+ N others" is computed client-side from
   * `admittedCount`, not from array length.
   */
  socialProof?: {
    admittedCount: number;
    avatars: { alias: string; avatarColor: string }[];
    previewAliases: string[];
  };
  /**
   * Present regardless of `view` — a coordinator is still a normal player
   * first (EVENT-OPS.md §1). Null when the current registration is not an
   * active coordinator of any room. This is a UI signal for whether to
   * show an entry point to /coordinate — the actual authorization for
   * every coordinator action is enforced server-side on each call, not by
   * this field. Migration 0029.
   */
  coordinating?: { roomId: string; roomLabel: string } | null;
  /** Present only once the room stage is settled (QUALIFIED / NOT_QUALIFIED
   * / FINALE / RESULTS). */
  championship?: Championship | null;
};

export type CheckInResult =
  | { ok: true; state: PlayerState }
  | { ok: false; code: string; message: string };
