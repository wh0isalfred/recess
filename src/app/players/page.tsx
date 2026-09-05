import { resolvePlayerIdentity } from "@/features/pass/actions";
import { IdentityCheckFailed } from "@/components/shared/IdentityCheckFailed";
import { redirect } from "next/navigation";
import { PlayerShell } from "@/features/player-shell/PlayerShell";

/**
 * Minimal placeholder — REFERENCE in docs/SCREEN-STATUS.md, not a designed
 * screen. Exists only so the new bottom nav (Player Shell V2) has somewhere
 * real to link to instead of a 404. Do not treat this as the Players design;
 * it isn't one.
 */
export default async function PlayersPage() {
  const identity = await resolvePlayerIdentity();
  if (identity.status === "unregistered") redirect("/register");
  if (identity.status === "unknown") return <IdentityCheckFailed />;

  return (
    <PlayerShell active="players">
      <div className="rc-shell-placeholder">
        <p>Players is coming soon.</p>
      </div>
    </PlayerShell>
  );
}
