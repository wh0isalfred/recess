import { PlayerAvatar } from "@/components/brand/v2/PlayerAvatar";
import type { PlayerState } from "@/features/pass/types";

/**
 * Renders `state.socialProof` (migration 0020) — never invents players, never
 * randomizes order (server already sorts by player_number), never shows more
 * than the 6 avatars/3 aliases the server sends. The remainder in the text
 * ("+ N others") is computed from `admittedCount`, the real total, not from
 * how many names happened to come down the wire.
 */
export function SocialProof({ socialProof }: { socialProof: NonNullable<PlayerState["socialProof"]> }) {
  const { admittedCount, avatars, previewAliases } = socialProof;

  if (admittedCount < 1) return null;

  const remainder = Math.max(0, admittedCount - previewAliases.length);
  const namesText =
    previewAliases.length > 0
      ? remainder > 0
        ? `${previewAliases.join(", ")} + ${remainder} other${remainder === 1 ? "" : "s"}`
        : previewAliases.join(", ")
      : null;

  return (
    <div className="rc-pass2-social">
      <div className="rc-pass2-social-stack">
        {avatars.map((a, i) => (
          <PlayerAvatar
            key={`${a.alias}-${i}`}
            alias={a.alias}
            color={a.avatarColor}
            size={1.75}
            ring
            className="rc-pass2-social-avatar"
          />
        ))}
      </div>
      <div className="rc-pass2-social-divider" aria-hidden="true" />
      <div className="rc-pass2-social-text">
        <p className="rc-pass2-social-count">
          {admittedCount} {admittedCount === 1 ? "PLAYER IS IN" : "PLAYERS ARE IN"}
        </p>
        {namesText ? <p className="rc-pass2-social-names">{namesText}</p> : null}
      </div>
    </div>
  );
}
