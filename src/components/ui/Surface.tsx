import type { ReactNode } from "react";

export type Ground = "paper" | "night";
export type Grain = "high" | "mid" | "low" | "none";

/**
 * The only component allowed to set a ground colour.
 *
 * Cream before the event, aubergine from check-in onward. Everything nested
 * inside reads the semantic `ground` / `fg` colours, so the whole emotional
 * transition described in BRAND.md is one prop change per screen rather than
 * a theme audit.
 */
export function Surface({
  ground = "paper",
  grain = "mid",
  as: Tag = "div",
  className = "",
  children,
}: {
  ground?: Ground;
  grain?: Grain;
  as?: "div" | "main" | "section" | "aside";
  className?: string;
  children: ReactNode;
}) {
  return (
    <Tag
      data-ground={ground}
      data-grain={grain}
      className={`rc-grain relative isolate bg-ground text-fg ${className}`}
    >
      {children}
    </Tag>
  );
}
