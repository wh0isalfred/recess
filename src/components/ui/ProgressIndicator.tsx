/**
 * Two shapes, one idea: where am I in a sequence.
 *
 * "steps" is registration, 1 of 3, where the person can see the end and it is
 * close. "rounds" is a game in progress, round 2 of 4, where the bar answers
 * how much of this game is left. Both are labelled in words as well as drawn,
 * so neither depends on the graphic alone.
 */
export function ProgressIndicator({
  current,
  total,
  variant = "steps",
  label,
}: {
  current: number;
  total: number;
  variant?: "steps" | "rounds";
  label?: string;
}) {
  const clamped = Math.max(0, Math.min(current, total));
  const pct = total > 0 ? Math.round((clamped / total) * 100) : 0;

  if (variant === "steps") {
    return (
      <div className="relative z-10 flex items-center gap-3">
        <span className="rc-numeric text-rc-sm text-fg-soft">
          {clamped} / {total}
        </span>
        <span className="flex gap-1.5" role="img" aria-label={`Step ${clamped} of ${total}`}>
          {Array.from({ length: total }, (_, i) => (
            <span
              key={i}
              className={`block size-2 rounded-pill ${i < clamped ? "bg-accent" : "bg-fg-muted"}`}
            />
          ))}
        </span>
      </div>
    );
  }

  return (
    <div className="relative z-10">
      <div className="flex items-baseline justify-between">
        <p className="rc-label">{label ?? "Round"}</p>
        <p className="rc-numeric text-rc-sm text-fg-soft">
          {clamped} of {total}
        </p>
      </div>
      <div
        className="mt-2 h-2 w-full overflow-hidden rounded-pill bg-fg-muted"
        role="progressbar"
        aria-valuenow={clamped}
        aria-valuemin={0}
        aria-valuemax={total}
      >
        <div
          className="h-full rounded-pill bg-accent transition-[width] duration-[var(--t-state)] ease-[var(--ease-settle)]"
          style={{ width: `${pct}%` }}
        />
      </div>
    </div>
  );
}
