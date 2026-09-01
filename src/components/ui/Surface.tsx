import type { ReactNode } from "react";

export type Ground = "paper" | "night";
export type Grain = "high" | "mid" | "low" | "none";

/**
 * The only component allowed to set a ground.
 *
 * Cream before the event, aubergine from check-in onward. Everything nested
 * inside reads the semantic colours — ground, fg, accent-text, go, warn,
 * alert — so the whole emotional transition is one prop per screen rather
 * than a theme audit. State colours are redefined per ground so that every
 * one of them clears 4.5:1 wherever it lands.
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
  as?: "div" | "main" | "section" | "aside" | "article";
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

/**
 * A panel sitting on the current ground. Flat, hairline-bordered, no blur.
 * Paper does not float.
 */
export function Panel({
  as: Tag = "div",
  className = "",
  children,
}: {
  as?: "div" | "section" | "article" | "li";
  className?: string;
  children: ReactNode;
}) {
  return (
    <Tag
      className={`relative z-10 rounded-surface border-[length:var(--hairline)] border-fg-line bg-ground-lift/40 ${className}`}
    >
      {children}
    </Tag>
  );
}
