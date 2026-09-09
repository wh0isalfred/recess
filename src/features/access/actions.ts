"use server";

import { createClient } from "@/lib/supabase/server";

type ActionResult<T> = { ok: true; data: T } | { ok: false; code: string; message: string };

const FRIENDLY: Record<string, string> = {
  not_authenticated: "Your session expired — please request a new code.",
  phone_not_verified: "We couldn't verify that code. Please try again.",
  player_not_found: "We couldn't find a RECESS registration for that number.",
  identity_conflict: "Something went wrong recognizing this device. Please try again.",
};
const GENERIC = "Something went wrong. Please try again.";

function toFriendly(message: string): { code: string; message: string } {
  const [code] = message.split(":");
  return { code: code ?? "unknown", message: FRIENDLY[code ?? ""] ?? GENERIC };
}

/**
 * Called immediately after a successful client-side verifyOtp() — that
 * call is what actually proves phone ownership (Supabase's own OTP
 * verification, not anything RECESS invents). This server action then
 * runs recover_player_access(), which derives the phone from the now-
 * verified session's own auth.users row, never from anything passed here.
 */
export async function recoverPlayerAccess(): Promise<ActionResult<{ playerId: string; recovered: boolean }>> {
  const supabase = await createClient();
  const { data, error } = await supabase.rpc("recover_player_access");
  if (error) {
    const { code, message } = toFriendly(error.message);
    return { ok: false, code, message };
  }
  return { ok: true, data: data as { playerId: string; recovered: boolean } };
}
