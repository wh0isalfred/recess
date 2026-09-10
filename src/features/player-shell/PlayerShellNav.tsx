"use client";

import Link from "next/link";
import { usePathname } from "next/navigation";
import { PassIcon, GamesIcon, PlayersIcon, MoreIcon } from "@/components/brand/v2/icons";

const TABS = [
  { key: "pass", href: "/pass", label: "Pass", Icon: PassIcon },
  { key: "games", href: "/games", label: "Games", Icon: GamesIcon },
  { key: "players", href: "/players", label: "Players", Icon: PlayersIcon },
  { key: "more", href: "/more", label: "More", Icon: MoreIcon },
] as const;

/**
 * The one stable piece of registered-player navigation — see
 * ARCHITECTURE.md-equivalent framing in the brief: "stable places, dynamic
 * content." Fixed to the viewport bottom, safe-area aware, aligned to the
 * same bounded canvas as the rest of the shell on desktop (not stretched
 * across the browser). Active tab is a color change only (pink vs neutral)
 * plus `aria-current="page"` — never a floating pill, never glassmorphism.
 *
 * Phase 8.2: a Client Component reading the pathname itself, rather than
 * receiving `active` as a prop from whichever page happened to render it —
 * since this is now rendered exactly once, by the shared (player) layout,
 * there is no per-page prop to receive it from. `startsWith` (not exact
 * equality) so a future nested route under, say, /games/some-game still
 * highlights the Games tab correctly.
 */
export function PlayerShellNav() {
  const pathname = usePathname();

  return (
    <nav className="rc-shell-nav" aria-label="RECESS">
      <div className="rc-shell-nav-inner">
        {TABS.map(({ key, href, label, Icon }) => {
          const isActive = pathname === href || pathname.startsWith(`${href}/`);
          return (
            <Link
              key={key}
              href={href}
              className="rc-shell-nav-tab"
              data-active={isActive}
              aria-current={isActive ? "page" : undefined}
            >
              <Icon className="rc-shell-nav-icon" />
              <span className="rc-shell-nav-label">{label}</span>
            </Link>
          );
        })}
      </div>
    </nav>
  );
}
