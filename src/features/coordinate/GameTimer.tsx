"use client";

import { useEffect, useState } from "react";

/**
 * Renders a live countdown purely as a function of two authoritative
 * values — room_event_games.started_at and event_games.duration_minutes —
 * recomputed every second from those timestamps, never from a locally
 * ticking value that could drift or get persisted. A reload recomputes
 * from the same two values, so there is nothing to "recover" here; the
 * source of truth never left the server.
 */
export function GameTimer({
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

  if (durationMinutes === null || startedAt === null) {
    return <p className="rc-coord-timer rc-coord-timer--none">No time limit configured</p>;
  }

  const endsAt = new Date(startedAt).getTime() + durationMinutes * 60_000;
  const remainingMs = endsAt - now;
  const expired = remainingMs <= 0;
  const totalSeconds = Math.max(0, Math.floor(remainingMs / 1000));
  const minutes = Math.floor(totalSeconds / 60);
  const seconds = totalSeconds % 60;

  return (
    <p className={`rc-coord-timer rc-numeric ${expired ? "rc-coord-timer--expired" : ""}`}>
      {expired ? "TIME'S UP" : `${minutes}:${seconds.toString().padStart(2, "0")} remaining`}
    </p>
  );
}
