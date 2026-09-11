"use server";

import { createClient } from "@/lib/supabase/server";

type ActionResult<T> = { ok: true; data: T } | { ok: false; message: string };

const GENERIC = "Something went wrong. Please try again.";

export type GameProgressItem = {
  slug: string;
  name: string;
  platform: string;
  artworkUrl: string | null;
  plannedRounds: number;
  status: "PENDING" | "LIVE" | "COMPLETE";
  completedRounds: number;
  yourGamePoints: number | null;
};

export type MyRoomStandings = {
  room: string | null;
  standings: { alias: string; totalPoints: number; placement: number }[] | null;
};

/** /games — zero arguments; entirely derived server-side from the caller's
 * own session via get_my_game_progress(). */
export async function fetchMyGameProgress(): Promise<ActionResult<GameProgressItem[]>> {
  const supabase = await createClient();
  const { data, error } = await supabase.rpc("get_my_game_progress");
  if (error) return { ok: false, message: GENERIC };
  return { ok: true, data: (data as GameProgressItem[]) ?? [] };
}

/** /players — zero arguments; entirely derived server-side from the
 * caller's own session via get_my_room_standings(). Never a registrationId
 * anywhere in the response. */
export async function fetchMyRoomStandings(): Promise<ActionResult<MyRoomStandings>> {
  const supabase = await createClient();
  const { data, error } = await supabase.rpc("get_my_room_standings");
  if (error) return { ok: false, message: GENERIC };
  return { ok: true, data: data as MyRoomStandings };
}
