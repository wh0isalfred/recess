import { PlayMark } from "@/components/brand/PlayMark";
import type { PlayerState } from "@/features/pass/types";

/**
 * QUALIFIED — the room stage is done and this player is through to the
 * finale. No finale engine exists yet (Gate C's concern) — this screen
 * only states the room-stage fact plainly, never a fabricated finale
 * countdown or state transition.
 */
export function QualifiedScreen({ state }: { state: PlayerState }) {
  const championship = state.championship;

  return (
    <div className="rc-live-stage">
      <PlayMark className="rc-live-mark" />
      <h1 className="rc-live-heading rc-numeric">YOU&rsquo;RE THROUGH.</h1>
      {championship ? (
        <p className="rc-live-points rc-numeric">
          {championship.yourTotalPoints} points
          {championship.roomPlacement !== null ? ` · placed ${championship.roomPlacement}` : ""}
        </p>
      ) : null}
      <p className="rc-live-support">
        {championship?.finaleInProgress ? "The finale is live." : "Finale is next."}
      </p>
    </div>
  );
}
