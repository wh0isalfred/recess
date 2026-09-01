import { StatusBadge, type StatusTone } from "./StatusBadge";

/**
 * A player as they appear everywhere but the leaderboard: rosters, room
 * lists, coordinator participation ticks, award recipients.
 *
 * The RECESS alias is the name. The player number is secondary and the
 * external game alias, when there is one, is shown underneath — that mapping
 * is the whole reason game_aliases exists.
 */
export function PlayerChip({
  alias,
  playerNumber,
  gameAlias,
  status,
  statusTone = "confirmed",
}: {
  alias: string;
  playerNumber?: number;
  gameAlias?: string;
  status?: string;
  statusTone?: StatusTone;
}) {
  return (
    <div className="relative z-10 flex items-center gap-3">
      {playerNumber !== undefined ? (
        <span className="rc-numeric shrink-0 rounded-surface bg-fg-muted px-2 py-1 text-rc-xs text-fg-soft">
          {String(playerNumber).padStart(3, "0")}
        </span>
      ) : null}

      <span className="min-w-0 flex-1">
        <span className="block truncate font-display text-rc-base tracking-[0.01em]">
          {alias}
        </span>
        {gameAlias ? (
          <span className="block truncate text-rc-xs text-fg-soft">
            in game: {gameAlias}
          </span>
        ) : null}
      </span>

      {status ? <StatusBadge tone={statusTone}>{status}</StatusBadge> : null}
    </div>
  );
}
