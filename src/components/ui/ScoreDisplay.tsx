export type ScoreSize = "sm" | "md" | "lg";

const sizes: Record<ScoreSize, string> = {
  sm: "text-rc-lg",
  md: "text-rc-xl",
  lg: "text-rc-2xl",
};

/**
 * A number that matters, with the smallest possible label under it.
 *
 * Used for points, position, days to go and round counts. The `delta` prop is
 * the +3 that stamps onto the screen when a result lands — the one piece of
 * non-user-triggered motion in the system, and it fires once.
 */
export function ScoreDisplay({
  value,
  label,
  size = "md",
  prefix,
  delta,
  tone = "default",
}: {
  value: number | string;
  label: string;
  size?: ScoreSize;
  /** "#" for a finishing position. */
  prefix?: string;
  delta?: number;
  tone?: "default" | "accent";
}) {
  return (
    <div className="relative z-10">
      <p className="rc-label">{label}</p>
      <p
        className={`rc-numeric font-display ${sizes[size]} ${
          tone === "accent" ? "text-accent-text" : "text-fg"
        }`}
      >
        {prefix ? <span className="text-fg-soft">{prefix}</span> : null}
        {value}
        {delta !== undefined ? (
          <span className="rc-stamp ml-3 inline-block align-middle text-rc-md text-go">
            {delta > 0 ? `+${delta}` : delta}
          </span>
        ) : null}
      </p>
    </div>
  );
}
