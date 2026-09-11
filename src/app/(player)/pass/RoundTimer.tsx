"use client";

import { useEffect, useState } from "react";

/**
 * A quiet, live countdown computed purely from two authoritative values —
 * room_event_games.started_at and event_games.duration_minutes — same
 * principle as the coordinator's own GameTimer, but a calmer, non-urgent
 * treatment appropriate for a player's own screen (this isn't the
 * coordinator's operational clock). Never fabricates a duration when
 * none is configured, and recomputes fresh on every reload — nothing is
 * ever persisted client-side.
 */
export function RoundTimer({
  startedAt,
  durationMinutes,
}: {
  startedAt: string | null;
  durationMinutes: number | null;
}) {
  const [now, setNow] = useState(() => Date.now());

  useEffect(() => {
    if (durationMinutes === null || startedAt === null) return;
    const id = setInterval(() => setNow(Date.now()), 1000);
    return () => clearInterval(id);
  }, [durationMinutes, startedAt]);

  if (durationMinutes === null || startedAt === null) return null;

  const endsAt = new Date(startedAt).getTime() + durationMinutes * 60_000;
  const remainingMs = endsAt - now;
  if (remainingMs <= 0) return null; // expiry is handled by awaitingGameSettlement, not a "time's up" flash here

  const totalSeconds = Math.floor(remainingMs / 1000);
  const minutes = Math.floor(totalSeconds / 60);
  const seconds = totalSeconds % 60;

  return (
    <p className="rc-live-timer rc-numeric">
      {minutes}:{seconds.toString().padStart(2, "0")} remaining
    </p>
  );
}
