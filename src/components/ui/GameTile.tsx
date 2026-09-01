import { StatusBadge } from "./StatusBadge";

export type GamePlatform = "BROWSER" | "INSTALL" | "NATIVE";

const platformLabel: Record<GamePlatform, string> = {
  BROWSER: "Plays in your browser",
  INSTALL: "Install the app first",
  NATIVE: "Native app",
};

/**
 * A game in this edition. Used twice: on the landing page to say what the
 * night is, and on the Event Pass under "get ready" to say what to install
 * before Friday. The platform line exists to answer the only question a
 * player actually has, which is whether they need to download something.
 */
export function GameTile({
  name,
  platform,
  rounds,
  live = false,
  position,
}: {
  name: string;
  platform: GamePlatform;
  rounds?: number;
  live?: boolean;
  /** Running order. Only passed where the order is real information. */
  position?: number;
}) {
  return (
    <div className="relative z-10 flex items-center gap-4 border-b-[length:var(--hairline)] border-fg-line py-4 last:border-b-0">
      {position !== undefined ? (
        <span className="rc-numeric font-display text-rc-md text-fg-faint">
          {position}
        </span>
      ) : null}

      <div className="min-w-0 flex-1">
        <h3 className="truncate font-display text-rc-md">{name}</h3>
        <p className="text-rc-sm text-fg-soft">
          {platformLabel[platform]}
          {rounds ? ` · ${rounds} rounds` : ""}
        </p>
      </div>

      {live ? (
        <StatusBadge tone="live" pulse>
          Live now
        </StatusBadge>
      ) : platform === "INSTALL" ? (
        <StatusBadge tone="waiting">Install</StatusBadge>
      ) : null}
    </div>
  );
}
