import { resolvePlayerIdentity } from "@/features/pass/actions";
import { IdentityCheckFailed } from "@/components/shared/IdentityCheckFailed";
import { redirect } from "next/navigation";
import { PlayerShell } from "@/features/player-shell/PlayerShell";

/**
 * Minimal placeholder — REFERENCE in docs/SCREEN-STATUS.md, not a designed
 * screen. Exists only so the new bottom nav (Player Shell V2) has somewhere
 * real to link to instead of a 404. Do not treat this as the Games design;
 * it isn't one.
 */
export default async function GamesPage() {
  const identity = await resolvePlayerIdentity();
  if (identity.status === "unregistered") redirect("/register");
  if (identity.status === "unknown") return <IdentityCheckFailed />;

  return (
    <PlayerShell active="games">
      <div className="rc-shell-placeholder">
        <p>Games is coming soon.</p>
      </div>
    </PlayerShell>
  );
}
