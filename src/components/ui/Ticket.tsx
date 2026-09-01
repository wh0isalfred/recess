import type { ReactNode } from "react";

/**
 * The signature object.
 *
 * A die-cut stub with notches punched out of both sides, holding the one
 * number a player quotes to other people: their player number at registration
 * and their finishing position at the end. It is the only component in the
 * system that is allowed to look like an artefact rather than an interface,
 * and it earns that because those are the two moments RECESS wants people to
 * screenshot.
 *
 * Everything else stays quiet so this can be loud.
 */
export function Ticket({
  label,
  value,
  footnote,
  children,
}: {
  label: string;
  value: string;
  footnote?: string;
  children?: ReactNode;
}) {
  return (
    <div className="relative z-10 inline-block">
      <div className="rc-ticket rounded-ticket bg-paper-deep px-10 py-6 text-center">
        <p className="rc-label text-ink-soft">{label}</p>
        <p className="rc-numeric mt-1 font-display text-rc-2xl text-ink">{value}</p>
        {footnote ? (
          <p className="mt-2 text-rc-xs text-ink-soft">{footnote}</p>
        ) : null}
        {children}
      </div>
    </div>
  );
}
