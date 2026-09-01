export type StatusTone = "live" | "confirmed" | "waiting" | "inactive" | "info";

const tones: Record<StatusTone, { className: string; glyph: string }> = {
  // Every tone carries a glyph as well as a colour. Nothing in RECESS is
  // communicated by colour alone.
  live: { className: "bg-accent text-paper", glyph: "●" },
  confirmed: { className: "bg-go-wash text-go", glyph: "✓" },
  waiting: { className: "bg-warn-wash text-warn", glyph: "◷" },
  inactive: { className: "bg-fg-muted text-fg-soft", glyph: "–" },
  info: { className: "border-[length:var(--hairline)] border-fg-line text-info", glyph: "•" },
};

/**
 * LIVE NOW, YOU'RE IN, WAITING FOR A ROOM, DNP. Small, dense, and always
 * legible at a glance across a coordinator's roster.
 */
export function StatusBadge({
  children,
  tone = "info",
  pulse = false,
}: {
  children: string;
  tone?: StatusTone;
  pulse?: boolean;
}) {
  const { className, glyph } = tones[tone];

  return (
    <span
      className={`inline-flex items-center gap-1.5 rounded-pill px-2.5 py-1 text-rc-xs font-medium tracking-[0.08em] uppercase ${className}`}
    >
      <span
        aria-hidden="true"
        className={pulse ? "animate-pulse motion-reduce:animate-none" : undefined}
      >
        {glyph}
      </span>
      {children}
    </span>
  );
}
