import { PlayerAvatar } from "@/components/brand/v2/PlayerAvatar";
import { formatPlayerNumber } from "@/features/registration/calendar";

/**
 * "WH0ISALFRED / #024" with the player's own persistent avatar — public
 * alias only, never real name or phone. `formatPlayerNumber` (unchanged,
 * already used by the pre-V2 Pass/Registration screens) pads to 3 digits
 * and never truncates above 999.
 */
export function PlayerIdentity({
  alias,
  playerNumber,
  avatarColor,
}: {
  alias: string;
  playerNumber: number;
  avatarColor: string;
}) {
  return (
    <div className="rc-shell-identity">
      <PlayerAvatar alias={alias} color={avatarColor} size={2.25} />
      <span className="rc-shell-identity-text">
        <span className="rc-shell-identity-alias rc-numeric">{alias.toUpperCase()}</span>
        <span className="rc-shell-identity-number rc-numeric">{formatPlayerNumber(playerNumber)}</span>
      </span>
    </div>
  );
}
