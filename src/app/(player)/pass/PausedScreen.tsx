import { PlayMark } from "@/components/brand/PlayMark";

/**
 * PAUSED — light, calm, unmistakable. No game controls, no fake timer,
 * no error styling. The underlying room/round facts stay exactly as they
 * were in the database; the next refresh after resume recomputes the
 * correct normal state on its own — nothing here needs to "remember"
 * where the player was.
 */
export function PausedScreen() {
  return (
    <div className="rc-live-stage rc-live-stage--paused">
      <PlayMark className="rc-live-mark" />
      <h1 className="rc-live-heading rc-numeric">PLAY IS PAUSED.</h1>
      <p className="rc-live-support">Hang tight. We&rsquo;ll be back.</p>
    </div>
  );
}
