"use server";

import { createClient } from "@/lib/supabase/server";
import type {
  CoordinatorRoomState,
  ResultPreview,
  RoomStandingRow,
  RoundSnapshot,
  SubmitResultOutcome,
} from "./types";

type ActionResult<T> = { ok: true; data: T } | { ok: false; code: string; message: string };

/**
 * Friendly text for every error code the scoring-engine functions this
 * feature calls can raise (0021/0025/0027/0028/0029). Unlisted codes fall
 * through to a generic message — no raw Postgres error ever reaches the
 * coordinator.
 */
const FRIENDLY: Record<string, string> = {
  not_authorized: "You're not the coordinator for this room.",
  room_not_found: "That room doesn't exist.",
  room_game_not_live: "This game hasn't been started for your room yet.",
  room_game_not_found: "This game hasn't been started for your room yet.",
  round_already_live: "A round is already in progress.",
  rounds_exhausted: "You've already played the maximum number of rounds for this game.",
  game_window_expired: "This game's time window has ended. An Admin can extend it.",
  round_not_found: "That round doesn't exist.",
  round_voided: "That round was voided and can't receive a result.",
  invalid_participant: "That result doesn't match who's actually in this round.",
  payload_participant_mismatch: "That result doesn't match exactly who's in this round — check for anyone missed or entered twice.",
  invalid_payload: "That result is missing something RECESS needs.",
  invalid_idempotency_key: "Something went wrong preparing that submission — please retry.",
  idempotency_key_reused: "That submission doesn't match this round — please retry.",
  correction_requires_request: "This round already has a confirmed result — request a correction instead.",
  no_confirmed_result: "This round doesn't have a confirmed result yet.",
  correction_already_pending: "A correction request for this result is already waiting on Admin review.",
  invalid_reason: "A reason is required.",
  round_still_live: "Finish or void the current round before ending this game.",
  room_game_not_ready: "This room hasn't reached the round count or time yet.",
};

const GENERIC = "Something went wrong. Please try again.";

function toFriendly(message: string): { code: string; message: string } {
  const [code] = message.split(":");
  return { code: code ?? "unknown", message: FRIENDLY[code ?? ""] ?? GENERIC };
}

async function callRpc<T>(fn: string, args: Record<string, unknown>): Promise<ActionResult<T>> {
  const supabase = await createClient();
  const { data, error } = await supabase.rpc(fn, args);
  if (error) {
    const { code, message } = toFriendly(error.message);
    return { ok: false, code, message };
  }
  return { ok: true, data: data as T };
}

export async function fetchCoordinatorRoomState(roomId: string): Promise<ActionResult<CoordinatorRoomState>> {
  return callRpc<CoordinatorRoomState>("coordinator_room_state", { p_room_id: roomId });
}

export async function startRoomGame(roomId: string, eventGameId: string): Promise<ActionResult<{ roomId: string; eventGameId: string; status: string }>> {
  return callRpc("start_room_game", { p_room_id: roomId, p_event_game_id: eventGameId });
}

export async function startRound(roomId: string, eventGameId: string): Promise<ActionResult<RoundSnapshot>> {
  return callRpc<RoundSnapshot>("start_round", { p_room_id: roomId, p_event_game_id: eventGameId });
}

export async function previewRoundResult(roundId: string, payload: unknown): Promise<ActionResult<ResultPreview>> {
  return callRpc<ResultPreview>("preview_round_result", { p_round_id: roundId, p_payload: payload });
}

export async function submitRoundResult(
  roundId: string,
  payload: unknown,
  idempotencyKey: string,
): Promise<SubmitResultOutcome> {
  const result = await callRpc<{ roundId: string; resultId: string; idempotent: boolean }>(
    "submit_round_result",
    { p_round_id: roundId, p_payload: payload, p_idempotency_key: idempotencyKey },
  );
  if (!result.ok) return result;
  return { ok: true, roundId: result.data.roundId, resultId: result.data.resultId, idempotent: result.data.idempotent };
}

export async function completeRoomGame(roomId: string, eventGameId: string): Promise<ActionResult<{ roomId: string; eventGameId: string; status: string }>> {
  return callRpc("complete_room_game", { p_room_id: roomId, p_event_game_id: eventGameId });
}

export async function requestResultCorrection(
  roundId: string,
  proposedPayload: unknown,
  reason: string,
): Promise<ActionResult<{ requestId: string; status: string }>> {
  return callRpc("request_result_correction", {
    p_round_id: roundId,
    p_proposed_payload: proposedPayload,
    p_reason: reason,
  });
}

export async function fetchRoomStandings(roomId: string): Promise<ActionResult<RoomStandingRow[]>> {
  return callRpc<RoomStandingRow[]>("room_standings", { p_room_id: roomId });
}
