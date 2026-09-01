/**
 * One line of the standings.
 *
 * Position is `rank()`, so ties genuinely read 1, 2, 2, 4 — a tied row is
 * marked with an equals sign rather than being silently renumbered, because
 * two people sharing second place is a result, not a rendering problem.
 *
 * The viewer's own row is marked by a rule and a label, not by colour alone.
 */
export function LeaderboardRow({
  position,
  alias,
  points,
  tied = false,
  isSelf = false,
  breakdown,
}: {
  position: number;
  alias: string;
  points: number;
  tied?: boolean;
  isSelf?: boolean;
  /** e.g. "Skribbl +5 · Among Us +6 · Trivia +7" */
  breakdown?: string;
}) {
  return (
    <li
      className={`relative z-10 flex items-center gap-4 border-b-[length:var(--hairline)] border-fg-line py-3 last:border-b-0 ${
        isSelf ? "border-l-2 border-l-accent bg-accent-wash pl-3" : ""
      }`}
    >
      <span className="rc-numeric w-10 shrink-0 font-display text-rc-md text-fg-soft">
        {tied ? <span aria-label="tied">=</span> : null}
        {position}
      </span>

      <span className="min-w-0 flex-1">
        <span className="block truncate font-display text-rc-base">
          {alias}
          {isSelf ? (
            <span className="ml-2 text-rc-xs font-normal text-accent-text">you</span>
          ) : null}
        </span>
        {breakdown ? (
          <span className="block truncate text-rc-xs text-fg-soft">{breakdown}</span>
        ) : null}
      </span>

      <span className="rc-numeric shrink-0 font-display text-rc-md">{points}</span>
    </li>
  );
}
