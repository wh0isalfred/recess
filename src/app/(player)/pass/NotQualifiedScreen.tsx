import { PlayMark } from "@/components/brand/PlayMark";
import type { PlayerState } from "@/features/pass/types";

/**
 * NOT_QUALIFIED — plain, warm, never apologetic or humiliating. Their
 * own result stands on its own. Once the finale starts, this only ever
 * gains a calm, low-key note (finaleInProgress) — no live finalist
 * telemetry is exposed here by design (Gate A's locked decision).
 */
export function NotQualifiedScreen({ state }: { state: PlayerState }) {
  const championship = state.championship;

  return (
    <div className="rc-live-stage">
      <PlayMark className="rc-live-mark" />
      <h1 className="rc-live-heading rc-numeric">THAT&rsquo;S A WRAP FOR YOU TONIGHT.</h1>
      {championship ? (
        <p className="rc-live-points rc-numeric">{championship.yourTotalPoints} points</p>
      ) : null}
      {championship?.finaleInProgress ? (
        <p className="rc-live-support">The finale is happening now.</p>
      ) : null}
    </div>
  );
}
